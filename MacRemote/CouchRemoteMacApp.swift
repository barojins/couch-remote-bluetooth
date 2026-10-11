import SwiftUI

@main
struct CouchRemoteMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Couch Remote", systemImage: "computermouse") {
            MacMenu(host: appDelegate.host, showWindow: appDelegate.showWindow)
        }
    }
}

final class MacAppDelegate: NSObject, NSApplicationDelegate {
    let host = MacBluetoothHost()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(self, selector: #selector(showWindow),
                                               name: .remoteApprovalRequested, object: nil)
        showWindow()
    }

    @objc func showWindow() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 620),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Couch Remote"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MacSetupView(host: host))
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

private struct MacMenu: View {
    @ObservedObject var host: MacBluetoothHost
    var showWindow: () -> Void

    var body: some View {
        Text(host.message)
        Button("Open Couch Remote") { showWindow() }
        if host.approvalCode != nil {
            Button("Review connection request") { showWindow() }
        }
        Divider()
        Button(host.isEnabled ? "Pause remote control" : "Resume remote control") { host.toggleEnabled() }
        Button("Quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private struct MacSetupView: View {
    @ObservedObject var host: MacBluetoothHost

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Couch Remote", systemImage: "computermouse.fill")
                    .font(.largeTitle.bold())
                Text("Your iPhone. Your Mac. Your couch.").foregroundStyle(.secondary)
                Label(host.message, systemImage: host.isApproved ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                    .fixedSize(horizontal: false, vertical: true)

                if let code = host.approvalCode {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Does your iPhone show this code?").font(.headline)
                        Text(code).font(.system(size: 34, weight: .semibold, design: .monospaced))
                        HStack {
                            Button("Decline") { host.deny() }
                            Button("Trust this iPhone") {
                                host.approve()
                                if host.hasPermission { NSApplication.shared.hide(nil) }
                            }.buttonStyle(.borderedProminent)
                        }
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                }

                Label(host.hasPermission ? "Accessibility access enabled" : "Accessibility access required",
                      systemImage: host.hasPermission ? "checkmark.shield.fill" : "lock.shield")
                if !host.hasPermission {
                    Text("Allow CouchRemoteMac in System Settings → Privacy & Security → Accessibility so it can move the pointer and type.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Grant Accessibility access") { host.requestPermission() }
                }
                Text("Open Couch Remote on your iPhone and select this Mac. Approve your iPhone once; trusted phones reconnect automatically. Close this window to keep the receiver in the menu bar.")
                    .font(.callout).foregroundStyle(.secondary)
                LoginItemView()
                if !host.trustedPhones.isEmpty {
                    Divider()
                    Text("Trusted iPhones").font(.headline)
                    ForEach(host.trustedPhones, id: \.self) { id in
                        HStack {
                            Text("iPhone · \(id.uuidString.prefix(8))").font(.callout)
                            Spacer()
                            Button("Forget") { host.forgetPhone(id) }
                        }
                    }
                }
                Button(host.isEnabled ? "Pause remote control" : "Resume remote control") { host.toggleEnabled() }
            }
            .padding(28).frame(width: 420)
        }
        .frame(width: 420, height: 620)
    }
}
