import AppKit
import ApplicationServices

final class InputController {
    private var postedPosition: CGPoint?
    private var postedAt = -Double.infinity

    var hasPermission: Bool { AXIsProcessTrusted() && CGPreflightPostEventAccess() }

    func resetPointer() { postedPosition = nil }

    private var pointerLocation: CGPoint? {
        // Events post asynchronously. Preserve deltas when BLE delivers a burst
        // before WindowServer has applied the preceding mouse event.
        if ProcessInfo.processInfo.systemUptime - postedAt < 0.05, let postedPosition {
            return postedPosition
        }
        return CGEvent(source: nil)?.location
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func execute(_ command: RemoteCommand) {
        guard hasPermission else { return }
        switch command {
        case let .move(dx, dy):
            guard let point = pointerLocation else { return }
            let proposed = CGPoint(x: point.x + CGFloat(dx), y: point.y + CGFloat(dy))
            let bounds = displayBounds()
            // Clamp to the nearest real display, including TVs left/above the laptop.
            let target = bounds.map { rect in
                CGPoint(x: min(max(proposed.x, rect.minX), rect.maxX - 1),
                        y: min(max(proposed.y, rect.minY), rect.maxY - 1))
            }.min { a, b in
                hypot(a.x - proposed.x, a.y - proposed.y) < hypot(b.x - proposed.x, b.y - proposed.y)
            } ?? point
            let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                mouseCursorPosition: target, mouseButton: .left)
            event?.setIntegerValueField(.mouseEventDeltaX, value: Int64(target.x - point.x))
            event?.setIntegerValueField(.mouseEventDeltaY, value: Int64(target.y - point.y))
            event?.post(tap: .cghidEventTap)
            postedPosition = target
            postedAt = ProcessInfo.processInfo.systemUptime
        case .click: click(count: 1)
        case .rightClick: click(count: 1, button: .right)
        case .doubleClick:
            click(count: 1)
            click(count: 2)
        case let .scroll(dx, dy):
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0)
            event?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event?.post(tap: .cghidEventTap)
        case let .text(text):
            // CGEvent supports short UTF-16 strings; never split a surrogate pair.
            var units: [UniChar] = []
            for scalar in text.unicodeScalars {
                let next = Array(String(scalar).utf16)
                if units.count + next.count > 20 { postText(units); units.removeAll() }
                units.append(contentsOf: next)
            }
            if !units.isEmpty { postText(units) }
        case let .key(key):
            let codes: [RemoteKey: CGKeyCode] = [
                .returnKey: 36, .backspace: 51, .escape: 53, .space: 49,
                .left: 123, .right: 124, .up: 126, .down: 125, .tab: 48
            ]
            guard let code = codes[key] else { return }
            for down in [true, false] {
                CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)?.post(tap: .cghidEventTap)
            }
        }
    }

    private func displayBounds() -> [CGRect] {
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(32, &displays, &count) == .success else { return [] }
        return displays.prefix(Int(count)).map { CGDisplayBounds($0) }
    }

    private func click(count: Int64, button: CGMouseButton = .left) {
        guard let point = pointerLocation else { return }
        let types: [CGEventType] = button == .right ? [.rightMouseDown, .rightMouseUp] : [.leftMouseDown, .leftMouseUp]
        for type in types {
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)
            event?.setIntegerValueField(.mouseEventClickState, value: count)
            event?.post(tap: .cghidEventTap)
        }
    }

    private func postText(_ units: [UniChar]) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
            event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            event?.post(tap: .cghidEventTap)
        }
    }
}
