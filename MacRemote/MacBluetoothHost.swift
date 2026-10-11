import AppKit
import CoreBluetooth

final class MacBluetoothHost: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    @Published private(set) var message = "Starting Bluetooth…"
    @Published private(set) var approvalCode: String?
    @Published private(set) var isApproved = false
    @Published private(set) var hasPermission = false
    @Published private(set) var isEnabled = true

    private var manager: CBPeripheralManager!
    private var commandCharacteristic: CBMutableCharacteristic?
    private var statusCharacteristic: CBMutableCharacteristic?
    private var central: CBCentral?
    private var pendingStatuses: [UUID: (CBCentral, RemoteStatus)] = [:]
    private var permissionTimer: Timer?
    private let input = InputController()

    override init() {
        super.init()
        hasPermission = input.hasPermission
        manager = CBPeripheralManager(delegate: self, queue: .main)
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let granted = self.input.hasPermission
            guard granted != self.hasPermission else { return }
            self.hasPermission = granted
            if self.isApproved, let central = self.central {
                self.send(granted ? .ready : .permissionNeeded, to: central)
            }
        }
    }

    func requestPermission() { input.requestPermission() }

    func approve() {
        guard approvalCode != nil, let central else { return }
        isApproved = true
        approvalCode = nil
        hasPermission = input.hasPermission
        message = "iPhone connected"
        send(hasPermission ? .ready : .permissionNeeded, to: central)
    }

    func deny() {
        guard let central else { return }
        send(.denied, to: central)
        self.central = nil
        approvalCode = nil
        isApproved = false
        message = "Connection declined. Ready for another iPhone."
    }

    func toggleEnabled() {
        isEnabled.toggle()
        if isEnabled { publishService() }
        else {
            if let central { send(.denied, to: central) }
            manager.stopAdvertising()
            manager.removeAllServices()
            resetConnection()
            commandCharacteristic = nil
            statusCharacteristic = nil
            message = "Remote control paused"
        }
    }

    private func resetConnection() {
        input.resetPointer()
        central = nil
        approvalCode = nil
        isApproved = false
        pendingStatuses.removeAll()
    }

    private func publishService() {
        guard isEnabled, manager.state == .poweredOn else { return }
        manager.stopAdvertising()
        manager.removeAllServices()
        resetConnection()
        let command = CBMutableCharacteristic(type: CBUUID(string: RemoteService.command),
            properties: [.write, .writeWithoutResponse], value: nil, permissions: [.writeEncryptionRequired])
        let status = CBMutableCharacteristic(type: CBUUID(string: RemoteService.status),
            properties: [.read, .notify, .notifyEncryptionRequired], value: nil, permissions: [.readEncryptionRequired])
        commandCharacteristic = command
        statusCharacteristic = status
        let service = CBMutableService(type: CBUUID(string: RemoteService.service), primary: true)
        service.characteristics = [command, status]
        manager.add(service)
        message = "Preparing connection…"
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        resetConnection()
        commandCharacteristic = nil
        statusCharacteristic = nil
        switch peripheral.state {
        case .poweredOn:
            if isEnabled { publishService() } else { message = "Remote control paused" }
        case .poweredOff: message = "Turn on Bluetooth in System Settings."
        case .unauthorized: message = "Allow Bluetooth access in System Settings → Privacy & Security."
        case .unsupported: message = "This Mac does not support Bluetooth LE peripheral mode."
        default: message = "Bluetooth is starting…"
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard isEnabled, service.characteristics?.contains(where: { $0 === commandCharacteristic }) == true else { return }
        if let error { message = "Bluetooth service failed: \(error.localizedDescription)"; return }
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: RemoteService.service)],
            CBAdvertisementDataLocalNameKey: Host.current().localizedName ?? "Couch Remote Mac"
        ])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        message = error.map { "Cannot advertise: \($0.localizedDescription)" } ?? "Ready for your iPhone"
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        guard isEnabled, characteristic === statusCharacteristic else { return }
        if let existing = self.central {
            if existing.identifier == central.identifier {
                if isApproved { send(input.hasPermission ? .ready : .permissionNeeded, to: central) }
                else if let approvalCode { send(.pending(approvalCode), to: central) }
            } else { send(.busy, to: central) }
            return
        }
        self.central = central
        peripheral.setDesiredConnectionLatency(.low, for: central)
        let code = String(format: "%06d", Int.random(in: 0...999999))
        approvalCode = code
        isApproved = false
        message = "Compare the code on your iPhone, then allow control."
        send(.pending(code), to: central)
        // Bring the approval window forward; receiving input never steals focus.
        NotificationCenter.default.post(name: .remoteApprovalRequested, object: nil)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        guard characteristic === statusCharacteristic else { return }
        pendingStatuses.removeValue(forKey: central.identifier)
        guard self.central?.identifier == central.identifier else { return }
        resetConnection()
        message = "iPhone disconnected. Ready to reconnect."
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard let first = requests.first else { return }
        var commands: [RemoteCommand] = []
        for request in requests {
            guard isEnabled, isApproved, central?.identifier == request.central.identifier else {
                peripheral.respond(to: first, withResult: .insufficientAuthorization)
                return
            }
            guard input.hasPermission else {
                send(.permissionNeeded, to: request.central)
                peripheral.respond(to: first, withResult: .insufficientAuthorization)
                return
            }
            guard request.characteristic === commandCharacteristic, request.offset == 0,
                  let value = request.value, let command = RemoteCommand(data: value) else {
                peripheral.respond(to: first, withResult: .invalidAttributeValueLength)
                return
            }
            commands.append(command)
        }
        // Validate the complete write before producing any input events.
        commands.forEach { input.execute($0) }
        peripheral.respond(to: first, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard isEnabled, request.characteristic === statusCharacteristic else {
            peripheral.respond(to: request, withResult: .readNotPermitted)
            return
        }
        // Core Bluetooth enforces readEncryptionRequired before delivering this.
        // Reading the probe establishes encryption, but grants no control authority.
        guard request.offset <= RemoteService.pairingProbe.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = RemoteService.pairingProbe.subdata(in: request.offset..<RemoteService.pairingProbe.count)
        peripheral.respond(to: request, withResult: .success)
    }

    private func send(_ status: RemoteStatus, to central: CBCentral) {
        pendingStatuses[central.identifier] = (central, status)
        flushStatuses()
    }

    private func flushStatuses() {
        guard let statusCharacteristic, manager.state == .poweredOn else { return }
        for (id, entry) in Array(pendingStatuses) {
            guard manager.updateValue(entry.1.data, for: statusCharacteristic, onSubscribedCentrals: [entry.0]) else { return }
            pendingStatuses.removeValue(forKey: id)
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) { flushStatuses() }
}

extension Notification.Name {
    static let remoteApprovalRequested = Notification.Name("remoteApprovalRequested")
}
