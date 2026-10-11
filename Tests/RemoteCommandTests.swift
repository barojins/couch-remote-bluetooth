import Foundation
import XCTest
@testable import RemoteProtocol

final class RemoteCommandTests: XCTestCase {
    func testEncryptedProbeIsRequiredBeforeSubscription() {
        var handshake = PairingHandshake()
        handshake.begin()
        XCTAssertEqual(handshake.step, .readEncrypted)
        handshake.subscribed(succeeded: true, encryptionError: false)
        XCTAssertEqual(handshake.step, .readEncrypted)
        handshake.receivedProbe(RemoteService.pairingProbe, succeeded: true)
        XCTAssertEqual(handshake.step, .subscribeEncrypted)
        handshake.subscribed(succeeded: true, encryptionError: false)
        XCTAssertEqual(handshake.step, .complete)
    }

    func testInsufficientEncryptionRetriesProtectedReadOnlyOnce() {
        var handshake = PairingHandshake()
        handshake.begin()
        handshake.receivedProbe(RemoteService.pairingProbe, succeeded: true)
        handshake.subscribed(succeeded: false, encryptionError: true)
        XCTAssertEqual(handshake.step, .readEncrypted)
        handshake.receivedProbe(RemoteService.pairingProbe, succeeded: true)
        handshake.subscribed(succeeded: false, encryptionError: true)
        XCTAssertEqual(handshake.step, .failed)
    }

    func testFailedOrUnexpectedProbeCannotEnableSubscription() {
        for (value, success) in [(RemoteService.pairingProbe, false), (Data("ready".utf8), true)] {
            var handshake = PairingHandshake()
            handshake.begin()
            handshake.receivedProbe(value, succeeded: success)
            XCTAssertEqual(handshake.step, .failed)
        }
        var handshake = PairingHandshake()
        handshake.begin()
        handshake.receivedProbe(RemoteService.pairingProbe, succeeded: true)
        handshake.subscribed(succeeded: false, encryptionError: false)
        XCTAssertEqual(handshake.step, .failed)
    }
    func testMovementUsesLittleEndianAndPreservesNegativeCoordinates() {
        XCTAssertEqual(RemoteCommand.move(-2, 258).data, Data([1, 1, 254, 255, 2, 1]))
        XCTAssertEqual(RemoteCommand(data: Data([1, 1, 254, 255, 2, 1])), .move(-2, 258))
        let extreme = RemoteCommand.move(.min, .max)
        XCTAssertEqual(RemoteCommand(data: extreme.data), extreme)
        XCTAssertLessThanOrEqual(extreme.data.count, 20)
    }

    func testAllControlsRoundTrip() {
        let commands: [RemoteCommand] = [.click, .doubleClick, .rightClick, .scroll(-120, 75), .text("검색 🎬 café")]
            + RemoteKey.allCases.map { .key($0) }
        for command in commands { XCTAssertEqual(RemoteCommand(data: command.data), command) }
    }

    func testMalformedCommandsCannotBecomeInput() {
        let invalid: [[UInt8]] = [[], [1], [2, 2], [1, 99], [1, 1, 0], [1, 2, 0],
                                  [1, 3, 0], [1, 4], [1, 4, 255], [1, 5, 255],
                                  [1, 5], [1, 5, 1, 0], [1, 4, 0], [1, 4, 27],
                                  [1, 6, 0], [1, 7], [1, 7, 0, 0, 0, 0, 0]]
        for bytes in invalid { XCTAssertNil(RemoteCommand(data: Data(bytes)), "Accepted \(bytes)") }
        XCTAssertNil(RemoteCommand(data: RemoteCommand.text(String(repeating: "a", count: 181)).data))
    }

    func testOnlyMovementAndScrollingCanStreamWithoutAcknowledgment() {
        XCTAssertTrue(RemoteCommand.move(1, 2).isContinuous)
        XCTAssertTrue(RemoteCommand.scroll(1, 2).isContinuous)
        for command in [RemoteCommand.click, .doubleClick, .rightClick, .key(.returnKey), .text("a")] {
            XCTAssertFalse(command.isContinuous)
        }
    }

    func testCoalescingPreservesClickAndGestureBoundaries() {
        XCTAssertEqual(RemoteCommand.move(5, -7).coalesced(with: .move(-2, 3)), .move(3, -4))
        XCTAssertEqual(RemoteCommand.scroll(5, -7).coalesced(with: .scroll(-2, 3)), .scroll(3, -4))
        XCTAssertNil(RemoteCommand.move(1, 1).coalesced(with: .rightClick))
        XCTAssertNil(RemoteCommand.rightClick.coalesced(with: .move(1, 1)))
        XCTAssertNil(RemoteCommand.move(1, 1).coalesced(with: .scroll(1, 1)))
        XCTAssertEqual(RemoteCommand.move(.max, .min).coalesced(with: .move(5, -5)), .move(.max, .min))
    }

    func testSlowMotionPreservesFractionalDistanceAcrossSamples() {
        var motion = TrackpadMotion()
        var x = 0, y = 0
        for _ in 0..<10 {
            if case let .move(dx, dy)? = motion.delta(x: 0.625, y: -0.625, speed: 20) {
                x += Int(dx); y += Int(dy)
            }
        }
        XCTAssertEqual(x, 5)
        XCTAssertEqual(y, -5)
        XCTAssertNil(motion.delta(x: 0, y: 0, speed: 0))
    }

    func testMotionGainAndScrollDirection() {
        var slow = TrackpadMotion(), fast = TrackpadMotion(), scroll = TrackpadMotion()
        XCTAssertEqual(slow.delta(x: 10, y: -10, speed: 20), .move(8, -8))
        XCTAssertEqual(fast.delta(x: 10, y: -10, speed: 800), .move(30, -30))
        XCTAssertEqual(scroll.delta(x: 10, y: -10, speed: 800, scrolling: true), .scroll(10, -10))
    }

    func testTextSplitsAtMinimumBluetoothMTUWithoutLosingUnicode() throws {
        let text = String(repeating: "한글 👨‍👩‍👧‍👦 café e\u{301} ", count: 20)
        let commands = try XCTUnwrap(RemoteCommand.textCommands(text, maximumWriteLength: 20))
        var reconstructed = ""
        for command in commands {
            XCTAssertLessThanOrEqual(command.data.count, 20)
            XCTAssertEqual(RemoteCommand(data: command.data), command)
            guard case let .text(part) = command else { return XCTFail("Unexpected key") }
            reconstructed += part
        }
        XCTAssertEqual(reconstructed, text)
    }

    func testTextRespectsProtocolLimitOnLargerMTU() throws {
        let commands = try XCTUnwrap(RemoteCommand.textCommands(String(repeating: "가", count: 1000), maximumWriteLength: 512))
        XCTAssertGreaterThan(commands.count, 1)
        XCTAssertTrue(commands.allSatisfy { $0.data.count <= 182 && RemoteCommand(data: $0.data) != nil })
    }

    func testNewlineAndTabBecomeDedicatedKeys() {
        XCTAssertEqual(RemoteCommand.textCommands("a\nb\tc", maximumWriteLength: 20),
                       [.text("a"), .key(.returnKey), .text("b"), .key(.tab), .text("c")])
    }

    func testUnsafeControlCharactersAndOversizeTextAreRejectedAtomically() {
        XCTAssertNil(RemoteCommand.textCommands("hello\u{1b}world", maximumWriteLength: 20))
        XCTAssertNil(RemoteCommand.textCommands(String(repeating: "a", count: 4097), maximumWriteLength: 20))
        XCTAssertNil(RemoteCommand.textCommands("a", maximumWriteLength: 5))
        XCTAssertEqual(RemoteCommand.textCommands("", maximumWriteLength: 20), [])
    }

    func testStatusRoundTripAndMinimumNotificationSize() {
        let statuses: [RemoteStatus] = [.pending("000123"), .ready, .permissionNeeded, .denied, .busy]
        for status in statuses {
            XCTAssertEqual(RemoteStatus(data: status.data), status)
            XCTAssertLessThanOrEqual(status.data.count, 20)
        }
        for value in ["pending:123", "pending:abcdef", "pending:１２３４５６", "unknown", "ready "] {
            XCTAssertNil(RemoteStatus(data: Data(value.utf8)))
        }
    }
}
