import XCTest
@testable import RemoteProtocol

final class ConnectionMemoryTests: XCTestCase {
    func testApprovalSurvivesRelaunchAndRevocationIsPersistent() {
        let suite = "CouchRemoteTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = UUID(), other = UUID()
        let memory = ConnectionMemory(defaults: defaults)
        XCTAssertFalse(memory.trustedPhones.contains(first))
        memory.trust(first)
        memory.trust(first)
        memory.trust(other)
        let relaunched = ConnectionMemory(defaults: defaults)
        XCTAssertEqual(Set(relaunched.trustedPhones), [first, other])
        relaunched.forget(first)
        XCTAssertEqual(memory.trustedPhones, [other])
    }

    func testSelectedMacSurvivesRelaunchUntilUserChoosesAnother() {
        let suite = "CouchRemoteTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        let memory = ConnectionMemory(defaults: defaults)
        memory.rememberMac(id: id, name: "Living room")
        let relaunched = ConnectionMemory(defaults: defaults)
        XCTAssertEqual(relaunched.macID, id)
        XCTAssertEqual(relaunched.macName, "Living room")
        relaunched.forgetMac()
        XCTAssertNil(memory.macID)
        XCTAssertNil(memory.macName)
    }

    func testReconnectBackoffAndUserPause() {
        var policy = ReconnectPolicy()
        XCTAssertEqual((0..<8).compactMap { _ in policy.nextDelay(foreground: true, poweredOn: true, hasTarget: true) }, [1, 2, 4, 8, 16, 30, 30, 30])
        XCTAssertNil(policy.nextDelay(foreground: false, poweredOn: true, hasTarget: true))
        XCTAssertNil(policy.nextDelay(foreground: true, poweredOn: false, hasTarget: true))
        XCTAssertNil(policy.nextDelay(foreground: true, poweredOn: true, hasTarget: false))
        policy.connected()
        XCTAssertEqual(policy.nextDelay(foreground: true, poweredOn: true, hasTarget: true), 1)
        policy.pause()
        XCTAssertNil(policy.nextDelay(foreground: true, poweredOn: true, hasTarget: true))
        policy.resume()
        XCTAssertEqual(policy.nextDelay(foreground: true, poweredOn: true, hasTarget: true), 1)
    }
}
