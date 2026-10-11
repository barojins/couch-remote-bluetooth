import CoreBluetooth
import UIKit

struct NearbyMac: Identifiable {
    let peripheral: CBPeripheral
    let name: String
    var id: UUID { peripheral.identifier }
}

final class PhoneBluetoothClient: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published private(set) var devices: [NearbyMac] = []
    @Published private(set) var message = "Starting Bluetooth…"
    @Published private(set) var approvalCode: String?
    @Published private(set) var isReady = false
    @Published private(set) var isConnecting = false
    @Published private(set) var isScanning = false
    @Published private(set) var connectedName: String?
    @Published private(set) var isSendingText = false

    private var manager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var queue: [RemoteCommand] = []
    private var awaitingWrite = false
    private var timeout: Timer?
    private var textCompletion: ((Bool) -> Void)?
    private var foreground = true
    private var pairing = PairingHandshake()
    private let memory = ConnectionMemory()
    private var reconnectPolicy = ReconnectPolicy()
    private var reconnectTimer: Timer?
    private var targetID: UUID?
    private var targetName: String?

    override init() {
        super.init()
        targetID = memory.macID
        targetName = memory.macName
        manager = CBCentralManager(delegate: self, queue: .main)
    }

    func scan() {
        guard foreground, manager.state == .poweredOn, peripheral == nil else { return }
        devices.removeAll()
        manager.scanForPeripherals(withServices: [CBUUID(string: RemoteService.service)])
        isScanning = true
        message = "Looking for your Mac… Open Couch Remote on the Mac."
    }

    func connect(_ device: NearbyMac, automatic: Bool = false) {
        guard peripheral == nil, manager.state == .poweredOn else { return }
        targetID = device.id
        targetName = device.name
        if !automatic { reconnectPolicy.resume() }
        reconnectTimer?.invalidate()
        manager.stopScan()
        isScanning = false
        peripheral = device.peripheral
        connectedName = device.name
        isConnecting = true
        message = "Connecting to \(device.name)…"
        device.peripheral.delegate = self
        manager.connect(device.peripheral)
        // Core Bluetooth keeps a pending connection until the remembered Mac returns.
        // Discovery/pairing get their own deadlines after didConnect.
    }

    func chooseDifferentMac() {
        reconnectPolicy.pause()
        reconnectTimer?.invalidate()
        targetID = nil
        targetName = nil
        memory.forgetMac()
        disconnect(message: "Select your Mac to connect.", retry: false)
        scan()
    }

    private func reconnect() {
        guard foreground, !reconnectPolicy.isPaused, manager.state == .poweredOn, peripheral == nil else { return }
        if let id = targetID, let known = manager.retrievePeripherals(withIdentifiers: [id]).first {
            connect(NearbyMac(peripheral: known, name: targetName ?? known.name ?? "Your Mac"), automatic: true)
        } else { scan() }
    }

    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        guard let delay = reconnectPolicy.nextDelay(foreground: foreground,
            poweredOn: manager.state == .poweredOn, hasTarget: targetID != nil) else { return }
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.reconnect()
        }
    }

    private func disconnect(message: String, retry: Bool = true) {
        let previous = peripheral
        reset()
        if let previous { manager.cancelPeripheralConnection(previous) }
        self.message = message
        if retry { scheduleReconnect() }
    }

    func setForeground(_ active: Bool) {
        foreground = active
        if active {
            if peripheral == nil { reconnect() }
            else if peripheral?.state == .connected, isConnecting, approvalCode == nil {
                startTimeout(seconds: 30, message: "Restoring the connection…")
            }
        } else {
            manager.stopScan()
            isScanning = false
            reconnectTimer?.invalidate()
            // Keep the encrypted link, but never replay gestures or queued text after unlock.
            queue.removeAll()
            isSendingText = false
            let completion = textCompletion
            textCompletion = nil
            completion?(false)
        }
    }

    func send(_ command: RemoteCommand) {
        guard foreground, isReady, !isSendingText else { return }
        // Coalesce only adjacent motion, never across a click or key command.
        if let combined = queue.last?.coalesced(with: command) {
            queue[queue.count - 1] = combined
        } else {
            guard queue.count < 512 else {
                disconnect(message: "Connection is too slow. Reconnect before sending more input.")
                return
            }
            queue.append(command)
        }
        flush()
    }

    func sendText(_ text: String, completion: @escaping (Bool) -> Void) {
        guard foreground, isReady, !isSendingText, let peripheral,
              let commands = RemoteCommand.textCommands(text, maximumWriteLength: peripheral.maximumWriteValueLength(for: .withResponse)),
              !commands.isEmpty, queue.count + commands.count <= 512 else {
            message = "Send up to 4 KB of text at a time while connected."
            completion(false)
            return
        }
        isSendingText = true
        textCompletion = completion
        queue.append(contentsOf: commands)
        flush()
    }

    private func flush() {
        guard isReady, !awaitingWrite, let peripheral, let commandCharacteristic else { return }
        while let command = queue.first {
            let type: CBCharacteristicWriteType = command.isContinuous ? .withoutResponse : .withResponse
            if type == .withoutResponse && !peripheral.canSendWriteWithoutResponse {
                if timeout?.isValid != true {
                    startTimeout(seconds: 8, message: "Bluetooth stopped sending. Reconnect to continue.")
                }
                return
            }
            let data = command.data
            guard data.count <= peripheral.maximumWriteValueLength(for: type) else {
                disconnect(message: "This Bluetooth connection cannot carry the command. Reconnect and try again.")
                return
            }
            timeout?.invalidate()
            queue.removeFirst()
            // Stream motion, but keep click/key ordering and acknowledgments.
            awaitingWrite = type == .withResponse
            peripheral.writeValue(data, for: commandCharacteristic, type: type)
            if awaitingWrite {
                startTimeout(seconds: 8, message: "The Mac stopped responding. Text may have been partially sent; check the Mac before retrying.")
                return
            }
        }
        if isSendingText {
            isSendingText = false
            let completion = textCompletion
            textCompletion = nil
            completion?(true)
        }
    }

    private func reset() {
        timeout?.invalidate()
        timeout = nil
        peripheral = nil
        commandCharacteristic = nil
        pairing = PairingHandshake()
        queue.removeAll()
        awaitingWrite = false
        isReady = false
        isConnecting = false
        approvalCode = nil
        connectedName = nil
        isSendingText = false
        let completion = textCompletion
        textCompletion = nil
        completion?(false)
    }

    private func startTimeout(seconds: TimeInterval, message: String) {
        timeout?.invalidate()
        timeout = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.disconnect(message: message)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        reset()
        devices.removeAll()
        isScanning = false
        switch central.state {
        case .poweredOn: reconnect()
        case .poweredOff: message = "Turn on Bluetooth to connect to your Mac."
        case .unauthorized: message = "Allow Bluetooth for Couch Remote in iPhone Settings → Privacy & Security."
        case .unsupported: message = "Bluetooth LE is not supported on this device."
        default: message = "Bluetooth is starting…"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard !devices.contains(where: { $0.id == peripheral.identifier }) else { return }
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Nearby Mac"
        let device = NearbyMac(peripheral: peripheral, name: name)
        devices.append(device)
        if targetID == peripheral.identifier, !reconnectPolicy.isPaused {
            connect(device, automatic: true)
            return
        }
        message = "Select your Mac to connect."
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { return }
        startTimeout(seconds: 30, message: "Restoring the Bluetooth connection…")
        message = "Preparing secure Bluetooth connection…"
        peripheral.discoverServices([CBUUID(string: RemoteService.service)])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        disconnect(message: error?.localizedDescription ?? "Could not connect. Try again.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        let partialText = isSendingText
        reset()
        message = partialText ? "Disconnected. Text may be partially sent; check the Mac before retrying." : "Waiting for your Mac. Reconnecting automatically…"
        scheduleReconnect()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === self.peripheral else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: RemoteService.service) }) else {
            disconnect(message: error?.localizedDescription ?? "Mac remote service was not found.")
            return
        }
        peripheral.discoverCharacteristics([CBUUID(string: RemoteService.command), CBUUID(string: RemoteService.status)], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === self.peripheral else { return }
        guard error == nil,
              let command = service.characteristics?.first(where: { $0.uuid == CBUUID(string: RemoteService.command) }),
              let status = service.characteristics?.first(where: { $0.uuid == CBUUID(string: RemoteService.status) }) else {
            disconnect(message: error?.localizedDescription ?? "The Mac is missing remote-control characteristics.")
            return
        }
        commandCharacteristic = command
        guard status.properties.contains(.read), command.properties.contains(.writeWithoutResponse) else {
            disconnect(message: "Update and restart Couch Remote on your Mac, then reconnect.")
            return
        }
        pairing.begin()
        beginSecureRead(peripheral, characteristic: status)
    }

    private func beginSecureRead(_ peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        message = "Securing Bluetooth… Accept any pairing prompts on your iPhone and Mac."
        startTimeout(seconds: 90, message: "Bluetooth pairing timed out. Keep both devices unlocked and reconnect to try again.")
        peripheral.readValue(for: characteristic)
    }

    private func pairingFailure(_ error: Error?) {
        disconnect(message: "Could not secure Bluetooth. Keep both devices unlocked, accept any pairing prompts, and reconnect. \(error?.localizedDescription ?? "The Mac returned an unexpected pairing response.")")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, characteristic.uuid == CBUUID(string: RemoteService.status) else { return }
        if pairing.step == .subscribeEncrypted {
            let nsError = error as NSError?
            let encryptionError = nsError?.domain == CBATTErrorDomain &&
                [CBATTError.Code.insufficientEncryption.rawValue, CBATTError.Code.insufficientAuthentication.rawValue]
                    .contains(nsError?.code ?? -1)
            pairing.subscribed(succeeded: error == nil && characteristic.isNotifying, encryptionError: encryptionError)
            if pairing.step == .readEncrypted {
                beginSecureRead(peripheral, characteristic: characteristic)
                return
            }
            if pairing.step == .failed { pairingFailure(error); return }
        }
        if let error { pairingFailure(error); return }
        if !characteristic.isNotifying { disconnect(message: "The Mac paused remote control.") }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, characteristic.uuid == CBUUID(string: RemoteService.status) else { return }
        if pairing.step == .readEncrypted {
            pairing.receivedProbe(characteristic.value, succeeded: error == nil)
            guard pairing.step == .subscribeEncrypted else { pairingFailure(error); return }
            peripheral.setNotifyValue(true, for: characteristic)
            return
        }
        guard error == nil, let data = characteristic.value, let status = RemoteStatus(data: data) else {
            disconnect(message: "Could not read the Mac’s connection status.")
            return
        }
        if !awaitingWrite { timeout?.invalidate() }
        isConnecting = false
        switch status {
        case let .pending(code):
            approvalCode = code
            isReady = false
            message = "Approve this code in Couch Remote on your Mac."
        case .ready:
            rememberApprovedMac(peripheral)
            approvalCode = nil
            isReady = true
            message = "Connected over Bluetooth"
            flush()
        case .permissionNeeded:
            rememberApprovedMac(peripheral)
            approvalCode = nil
            isReady = false
            queue.removeAll()
            isSendingText = false
            let completion = textCompletion
            textCompletion = nil
            completion?(false)
            message = "Enable Accessibility access for CouchRemoteMac on the Mac."
        case .denied:
            reconnectPolicy.pause()
            disconnect(message: "The Mac declined or paused control. Choose your Mac again to reconnect.", retry: false)
        case .busy: disconnect(message: "Another iPhone is connected. Disconnect it on the Mac first.")
        }
    }

    private func rememberApprovedMac(_ peripheral: CBPeripheral) {
        memory.rememberMac(id: peripheral.identifier, name: connectedName ?? "Your Mac")
        reconnectPolicy.connected()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, characteristic === commandCharacteristic, awaitingWrite else { return }
        timeout?.invalidate()
        awaitingWrite = false
        if let error {
            disconnect(message: "Input was not accepted: \(error.localizedDescription). Text may be partially sent.")
            return
        }
        flush()
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { return }
        flush()
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard peripheral === self.peripheral,
              invalidatedServices.contains(where: { $0.uuid == CBUUID(string: RemoteService.service) }) else { return }
        disconnect(message: "The Mac restarted or paused its receiver. Reconnect to continue.")
    }
}
