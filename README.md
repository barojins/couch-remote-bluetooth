# Couch Remote — Bluetooth

An iPhone trackpad and keyboard for a Mac connected to a television. Native Swift/SwiftUI apps, using Bluetooth Low Energy directly. No server, account, or internet connection.

## What works in this first version

- Discover the Mac from the iPhone app over Bluetooth.
- Encrypted Bluetooth writes and notifications, plus explicit approval on the Mac for each connection. Compare the six-digit app code on both devices before allowing control; accept any separate system Bluetooth pairing prompts too.
- One-finger pointer movement with speed-based acceleration, tap/click, and double-tap/double-click.
- Two-finger tap for a context menu; two-finger sliding for pixel-based natural scrolling.
- Movement and scrolling stream using encrypted writes without responses and Bluetooth backpressure. Clicks and keyboard commands remain ordered, acknowledged writes. The Mac requests low connection latency.
- A keyboard composer with an inline send icon, plus Return, Backspace, Escape, Space, Tab, and arrow keys. Text goes to the focused Mac app.
- Multi-display pointer bounds, including a TV arranged to the left or above the Mac display.
- Pause/resume from the Mac menu bar. The iPhone disconnects when backgrounded or locked; open it and select the Mac again to reconnect.

This repository is Bluetooth-only. The separate [couch-remote-web](https://github.com/barojins/couch-remote-web) repository implements a Mac host and iPhone Safari remote over Wi-Fi. Dragging, momentum scrolling, modifier shortcuts, media-specific integrations, and waking a sleeping Mac are not implemented. This approximates familiar trackpad gestures; it does not reproduce Apple's trackpad hardware or private acceleration curve.

## Distribution

See [Apple Developer Program distribution](Docs/DISTRIBUTION.md) for TestFlight archives, Developer ID signing, and notarized Mac disk images. Paid membership and distribution credentials are not yet configured or verified. This repository does not claim App Store approval.

## Run on your devices

Requirements: Xcode with the iOS SDK, an iPhone running iOS 17 or later, and a Mac running macOS 13 or later with Bluetooth LE peripheral support. The simulator can show the UI but cannot validate the Bluetooth connection.

1. Open `CouchRemote.xcodeproj` in Xcode. The generated project is included; no dependencies need to be downloaded.
2. In **Signing & Capabilities**, select your development team for both targets. If needed, change the bundle identifiers to unique identifiers. You may use your personal team for local device testing subject to Apple's provisioning limits.
3. Select the **CouchRemoteMac** scheme and **My Mac**, then Run. Allow Bluetooth when macOS requests it.
4. In the Mac app, click **Grant Accessibility access**. Enable **CouchRemoteMac** in **System Settings → Privacy & Security → Accessibility** (the permission label may differ by macOS version). Keep the signed app at a stable path; rebuilding or moving it may require granting access again.
5. Connect the iPhone to Xcode, enable Developer Mode if requested, select **CouchRemotePhone** and your physical iPhone, then Run. Allow Bluetooth access.
6. Select your Mac on the phone. Accept system pairing prompts, compare the six-digit code, and click **Allow control** on the Mac. The setup window hides so it does not retain keyboard focus.
7. Move the pointer to your video app. For typing, first click its text/search field, open **Keyboard** on the phone, compose text, and tap the send arrow beside the text field. Direct keys act immediately on the Mac.

The Mac receiver stays alive after closing its setup window. Use its mouse-shaped menu bar item to open setup, pause control, or quit. Only one phone can control it at a time. There is no stored app-level approval: reconnecting needs fresh approval.

Keep `LSUIElement` set to `NO`. On the tested Mac, running as a UI agent caused macOS to reject encrypted Bluetooth pairing with “no one to handle the request”; running as a regular app allowed the system pairing prompt and the connection to succeed. Commands and status notifications still require Bluetooth encryption.

## Build and test

### Mac installer for another computer

Run `bash Scripts/PackageMac.sh` to create `dist/CouchRemote-macOS13-universal.dmg` with Intel and Apple Silicon executables. Open it on the destination Mac and drag CouchRemoteMac into Applications; Xcode is not needed there. macOS 13 or later and Bluetooth LE peripheral support are still required. This is an ad-hoc-signed personal test package, not a Developer ID notarized release, so macOS may block its first launch. The disk image includes installation instructions. Bluetooth and Accessibility permission must be granted on each Mac.

The disk image does not install the iPhone app. TestFlight distribution requires an Apple Developer Program membership and App Store Connect setup; its builds expire after 90 days. The existing free Personal Team installation remains a development-only route.

The checked-in Xcode project is generated from `project.yml`. After editing that configuration, regenerate with `xcodegen generate` (XcodeGen is already available on the development Mac).

Both apps use the `AppIcon` asset catalogs. Regenerate their native-size PNGs with `swift Scripts/GenerateAppIcons.swift`; the Mac icon includes transparent margins, while the iPhone icon is an opaque 1024 × 1024 image.

```sh
swift test
xcodebuild -project CouchRemote.xcodeproj -scheme CouchRemoteMac -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
xcodebuild -project CouchRemote.xcodeproj -scheme CouchRemotePhone -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath build-phone CODE_SIGNING_ALLOWED=NO build
```

Unsigned builds verify compilation; use Xcode signing for installation and Mac privacy permissions. `Tests/RemoteCommandTests.swift` covers malformed packets, control keys, negative pointer deltas, UTF-8 boundaries at the minimum BLE write size, text size limits, and status messages. These tests do not simulate Bluetooth or grant macOS permissions.

Verification on October 10, 2026: the Mac and signed iPhone builds passed with Xcode 27; all 15 protocol/motion tests passed. Physical Bluetooth pairing succeeded and the user confirmed remote input worked before the streaming-motion update. The updated pointer feel, two-finger gestures, display transitions, and video-app behavior still require the device checks below. Update both apps together for the new commands and streaming characteristic.

## Device acceptance checks

- With approval missing, neither pointer nor keyboard input should work.
- Decline a connection, reconnect, then approve it. Verify the code changes.
- Without Accessibility access, the phone should explain the missing permission; enable it and verify controls become available.
- Move across the Mac and TV displays, including negative display coordinates. Test clicking and double-clicking in Finder and the video app.
- Test slow precise strokes and fast swipes, then click immediately after moving. Tap with two fingers to open a context menu without a left click. Slide with two fingers to scroll without moving the pointer, and lift both fingers before switching back to one-finger movement.
- Type English, Korean, accented text, emoji, and a multiline string into TextEdit. Check Return, Space, Backspace, Escape, Tab, and arrow keys.
- Turn Bluetooth off, move out of range, lock/background the phone, and pause the Mac receiver. Verify input stops and reconnection requires approval.
- Interrupt a long text send. The original composer remains available on failure, but some text may already have arrived; check the Mac before retrying to avoid duplication.
- Try connecting a second phone while the first is approved. It should report the receiver is busy.

Text entry uses Unicode keyboard events rather than clipboard access. Apps using secure input, games, and some custom editors may ignore synthetic input or handle composed text differently. A successful BLE acknowledgment confirms receipt by the Mac receiver, not that the focused application accepted the text. Keep the Mac awake and the iPhone app foregrounded while controlling it.

## Layout

- `Shared/`: versioned command encoding and bounded UTF-8 text packetization.
- `MacRemote/`: encrypted BLE peripheral, session approval, permission checks, Core Graphics input events, and menu bar UI.
- `PhoneRemote/`: BLE discovery/connection, ordered acknowledged writes, motion coalescing, trackpad gestures, and keyboard UI.
- `Tests/`: protocol tests that run without paired devices.

No input is logged or persisted. The Mac app is intentionally not sandboxed because it posts system-wide input events; this is a local development build, not a notarized distribution or an App Store submission.

Ventura compatibility update: the Mac deployment target is macOS 13.0, and both Intel and Apple Silicon binaries were rebuilt and checked. Actual execution on a Ventura Mac still needs device testing; the current development Mac runs a newer macOS.
