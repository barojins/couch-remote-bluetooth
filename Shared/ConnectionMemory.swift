import Foundation

/// Identifiers are local Core Bluetooth identities, not advertised device names.
/// The Mac checks this allow-list only after an encrypted subscription succeeds.
final class ConnectionMemory {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var trustedPhones: [UUID] {
        (defaults.stringArray(forKey: "trustedPhones") ?? []).compactMap(UUID.init(uuidString:))
    }
    func trust(_ id: UUID) {
        defaults.set(Array(Set(trustedPhones + [id])).map(\.uuidString).sorted(), forKey: "trustedPhones")
    }
    func forget(_ id: UUID) {
        defaults.set(trustedPhones.filter { $0 != id }.map(\.uuidString), forKey: "trustedPhones")
    }
    var macID: UUID? { defaults.string(forKey: "rememberedMacID").flatMap(UUID.init(uuidString:)) }
    var macName: String? { defaults.string(forKey: "rememberedMacName") }
    func rememberMac(id: UUID, name: String) {
        defaults.set(id.uuidString, forKey: "rememberedMacID")
        defaults.set(name, forKey: "rememberedMacName")
    }
    func forgetMac() {
        defaults.removeObject(forKey: "rememberedMacID")
        defaults.removeObject(forKey: "rememberedMacName")
    }
}

struct ReconnectPolicy {
    private(set) var failures = 0
    private(set) var isPaused = false
    mutating func resume() { isPaused = false; failures = 0 }
    mutating func pause() { isPaused = true }
    mutating func connected() { failures = 0 }
    mutating func nextDelay(foreground: Bool, poweredOn: Bool, hasTarget: Bool) -> TimeInterval? {
        guard !isPaused, foreground, poweredOn, hasTarget else { return nil }
        let delay = min(pow(2, Double(min(failures, 5))), 30)
        failures += 1
        return delay
    }
}
