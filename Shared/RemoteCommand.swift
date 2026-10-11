import Foundation

enum RemoteService {
    static let service = "9D3D0001-754D-4B7A-A685-41223719C908"
    static let command = "9D3D0002-754D-4B7A-A685-41223719C908"
    static let status = "9D3D0003-754D-4B7A-A685-41223719C908"
    static let pairingProbe = Data("secure:1".utf8)
}

// An encrypted read must succeed before subscribing. Never fall back to plaintext.
struct PairingHandshake {
    enum Step: Equatable { case idle, readEncrypted, subscribeEncrypted, complete, failed }
    private(set) var step: Step = .idle
    private var retried = false

    mutating func begin() {
        step = .readEncrypted
        retried = false
    }

    mutating func receivedProbe(_ value: Data?, succeeded: Bool) {
        guard step == .readEncrypted else { return }
        step = succeeded && value == RemoteService.pairingProbe ? .subscribeEncrypted : .failed
    }

    mutating func subscribed(succeeded: Bool, encryptionError: Bool) {
        guard step == .subscribeEncrypted else { return }
        if succeeded { step = .complete }
        else if encryptionError && !retried {
            retried = true
            step = .readEncrypted
        } else { step = .failed }
    }
}

enum RemoteKey: UInt8, CaseIterable {
    case returnKey = 1, backspace, escape, space, left, right, up, down, tab

    var label: String {
        switch self {
        case .returnKey: return "Return"
        case .backspace: return "⌫"
        case .escape: return "Esc"
        case .space: return "Space"
        case .left: return "←"
        case .right: return "→"
        case .up: return "↑"
        case .down: return "↓"
        case .tab: return "Tab"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .backspace: return "Backspace"
        case .left: return "Left arrow"
        case .right: return "Right arrow"
        case .up: return "Up arrow"
        case .down: return "Down arrow"
        default: return label
        }
    }
}

// Version, opcode, then payload. Movement fits even the minimum BLE write size.
enum RemoteCommand: Equatable {
    case move(Int16, Int16)
    case click
    case doubleClick
    case rightClick
    case scroll(Int16, Int16)
    case text(String)
    case key(RemoteKey)

    var data: Data {
        switch self {
        case let .move(x, y), let .scroll(x, y):
            let x = UInt16(bitPattern: x), y = UInt16(bitPattern: y)
            let opcode: UInt8 = if case .scroll = self { 7 } else { 1 }
            return Data([1, opcode, UInt8(x & 255), UInt8(x >> 8), UInt8(y & 255), UInt8(y >> 8)])
        case .click: return Data([1, 2])
        case .doubleClick: return Data([1, 3])
        case .rightClick: return Data([1, 6])
        case let .text(text): return Data([1, 4]) + Data(text.utf8)
        case let .key(key): return Data([1, 5, key.rawValue])
        }
    }

    init?(data: Data) {
        let bytes = Array(data)
        guard bytes.count >= 2, bytes[0] == 1 else { return nil }
        switch bytes[1] {
        case 1, 7:
            guard bytes.count == 6 else { return nil }
            let x = Int16(bitPattern: UInt16(bytes[2]) | UInt16(bytes[3]) << 8)
            let y = Int16(bitPattern: UInt16(bytes[4]) | UInt16(bytes[5]) << 8)
            self = bytes[1] == 1 ? .move(x, y) : .scroll(x, y)
        case 2:
            guard bytes.count == 2 else { return nil }
            self = .click
        case 3:
            guard bytes.count == 2 else { return nil }
            self = .doubleClick
        case 4:
            guard bytes.count > 2, bytes.count <= 182,
                  let text = String(bytes: bytes.dropFirst(2), encoding: .utf8),
                  !text.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
            else { return nil }
            self = .text(text)
        case 5:
            guard bytes.count == 3, let key = RemoteKey(rawValue: bytes[2]) else { return nil }
            self = .key(key)
        case 6:
            guard bytes.count == 2 else { return nil }
            self = .rightClick
        default: return nil
        }
    }

    var isContinuous: Bool {
        switch self {
        case .move, .scroll: return true
        default: return false
        }
    }

    // Never combine movement across a click, a key, or a change of gesture.
    func coalesced(with next: RemoteCommand) -> RemoteCommand? {
        switch (self, next) {
        case let (.move(x, y), .move(dx, dy)):
            return .move(Int16(clamping: Int(x) + Int(dx)), Int16(clamping: Int(y) + Int(dy)))
        case let (.scroll(x, y), .scroll(dx, dy)):
            return .scroll(Int16(clamping: Int(x) + Int(dx)), Int16(clamping: Int(y) + Int(dy)))
        default: return nil
        }
    }

    // Split on scalar boundaries so each packet is independently valid UTF-8.
    static func textCommands(_ text: String, maximumWriteLength: Int) -> [RemoteCommand]? {
        let limit = min(180, maximumWriteLength - 2)
        guard limit >= 4, text.utf8.count <= 4096 else { return nil }
        var result: [RemoteCommand] = []
        var chunk = ""
        for scalar in text.unicodeScalars {
            if scalar.properties.generalCategory == .control {
                if !chunk.isEmpty { result.append(.text(chunk)); chunk = "" }
                switch scalar.value {
                case 10: result.append(.key(.returnKey))
                case 9: result.append(.key(.tab))
                default: return nil
                }
                continue
            }
            let next = String(scalar)
            if chunk.utf8.count + next.utf8.count > limit {
                result.append(.text(chunk))
                chunk = ""
            }
            chunk += next
        }
        if !chunk.isEmpty { result.append(.text(chunk)) }
        return result
    }
}

// Preserve sub-pixel movement; slow strokes aim precisely, quick strokes travel farther.
struct TrackpadMotion {
    private var remainderX = 0.0
    private var remainderY = 0.0

    mutating func delta(x: Double, y: Double, speed: Double, scrolling: Bool = false) -> RemoteCommand? {
        let t = min(1, max(0, (speed - 40) / 760))
        let gain = scrolling ? 1.0 : 0.8 + 2.2 * t * t * (3 - 2 * t)
        let scaledX = x * gain + remainderX
        let scaledY = y * gain + remainderY
        let dx = Int16(clamping: Int(scaledX)), dy = Int16(clamping: Int(scaledY))
        remainderX = scaledX - Double(dx)
        remainderY = scaledY - Double(dy)
        guard dx != 0 || dy != 0 else { return nil }
        return scrolling ? .scroll(dx, dy) : .move(dx, dy)
    }
}

enum RemoteStatus: Equatable {
    case pending(String), ready, permissionNeeded, denied, busy

    var data: Data {
        switch self {
        case let .pending(code): return Data("pending:\(code)".utf8)
        case .ready: return Data("ready".utf8)
        case .permissionNeeded: return Data("permission".utf8)
        case .denied: return Data("denied".utf8)
        case .busy: return Data("busy".utf8)
        }
    }

    init?(data: Data) {
        guard let value = String(data: data, encoding: .utf8) else { return nil }
        switch value {
        case "ready": self = .ready
        case "permission": self = .permissionNeeded
        case "denied": self = .denied
        case "busy": self = .busy
        default:
            guard value.hasPrefix("pending:"), value.count == 14,
                  value.suffix(6).allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            self = .pending(String(value.suffix(6)))
        }
    }
}
