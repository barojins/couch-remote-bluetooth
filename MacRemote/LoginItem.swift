import SwiftUI
import ServiceManagement

final class LoginItem: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var errorMessage: String?

    init() { refresh() }
    func refresh() {
        enabled = SMAppService.mainApp.status == .enabled
        needsApproval = SMAppService.mainApp.status == .requiresApproval
    }
    func setEnabled(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
        refresh()
    }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

struct LoginItemView: View {
    @StateObject private var login = LoginItem()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Launch at login", isOn: Binding(get: { login.enabled || login.needsApproval }, set: login.setEnabled))
            if login.needsApproval {
                Button("Approve in Login Items…") { login.openSettings() }
            }
            if let error = login.errorMessage { Text(error).font(.caption).foregroundStyle(.secondary) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh() }
    }
}
