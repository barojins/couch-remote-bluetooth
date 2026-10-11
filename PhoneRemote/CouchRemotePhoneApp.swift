import SwiftUI

@main
struct CouchRemotePhoneApp: App {
    @StateObject private var client = PhoneBluetoothClient()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RemoteView(client: client)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { client.setForeground(false) }
                    else if phase == .active { client.setForeground(true) }
                }
        }
    }
}

private struct RemoteView: View {
    @ObservedObject var client: PhoneBluetoothClient
    @State private var showKeyboard = false
    private let accent = Color(red: 0.66, green: 0.89, blue: 0.65)

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("COUCH REMOTE").font(.caption.weight(.semibold)).tracking(3).foregroundStyle(accent)
                        Text(client.connectedName ?? "Make yourself comfortable.")
                            .font(.title2.bold())
                    }
                    Spacer()
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(client.isReady ? accent : .secondary)
                }

                Text(client.message).font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("connectionStatus")

                if let code = client.approvalCode {
                    Text(code).font(.system(size: 40, weight: .semibold, design: .monospaced))
                        .tracking(6).padding().accessibilityLabel("Connection code \(code)")
                }

                if client.connectedName == nil {
                    connectionList
                } else {
                    trackpad
                    Button { showKeyboard = true } label: {
                        Label("Keyboard", systemImage: "keyboard")
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered).disabled(!client.isReady)
                    Button("Disconnect") { client.disconnect() }
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(24).background(Color(red: 0.055, green: 0.075, blue: 0.08))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showKeyboard) { KeyboardView(client: client).presentationDetents([.large]) }
            .tint(accent)
        }
    }

    private var connectionList: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.system(size: 64)).foregroundStyle(accent).accessibilityHidden(true)
            Text("Connect to your Mac").font(.title2.bold())
            Text("Open the Mac companion, then select it below. Keep Bluetooth enabled on both devices.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(client.devices) { device in
                        Button { client.connect(device) } label: {
                            HStack {
                                Label(device.name, systemImage: "laptopcomputer")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }.padding()
                        }.buttonStyle(.bordered)
                    }
                }
            }.frame(maxHeight: 220)
            Button("Search again") { client.scan() }.buttonStyle(.bordered)
            Spacer()
            Text("Bluetooth • No internet needed").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var trackpad: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(Color.white.opacity(0.045))
                .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(Color.white.opacity(0.12)))
            VStack(spacing: 14) {
                Image(systemName: "hand.draw").font(.system(size: 34, weight: .light))
                Text("Slide to move").font(.headline)
                Text("Tap to click · Double-tap to open").font(.caption)
                Text("Two fingers: tap to right-click · slide to scroll")
                    .font(.caption).multilineTextAlignment(.center)
            }.foregroundStyle(.secondary).allowsHitTesting(false)
            TrackpadView { client.send($0) }
                .clipShape(RoundedRectangle(cornerRadius: 30))
                .allowsHitTesting(client.isReady)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 200)
        .opacity(client.isReady ? 1 : 0.45)
    }
}

private struct KeyboardView: View {
    @ObservedObject var client: PhoneBluetoothClient
    @Environment(\.dismiss) private var dismiss
    @FocusState private var composing: Bool
    @State private var text = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .bottom, spacing: 8) {
                        TextField("Type…", text: $text, axis: .vertical)
                            .lineLimit(1...5).padding(12)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                            .focused($composing)
                            .disabled(client.isSendingText)
                            .accessibilityLabel("Text to send")
                            .accessibilityIdentifier("textComposer")
                        Button {
                            composing = false
                            client.sendText(text) { success in
                                if success { text = "" }
                            }
                        } label: {
                            Group {
                                if client.isSendingText {
                                    ProgressView()
                                } else {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 32))
                                }
                            }
                            .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .opacity(text.isEmpty || !client.isReady ? 0.4 : 1)
                        .accessibilityLabel(client.isSendingText ? "Sending" : "Send text")
                        .accessibilityIdentifier("sendText")
                        .disabled(text.isEmpty || !client.isReady || client.isSendingText)
                    }

                    Text("DIRECT KEYS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                        ForEach(RemoteKey.allCases, id: \.rawValue) { key in
                            Button { client.send(.key(key)) } label: {
                                Text(key.label).frame(maxWidth: .infinity).padding(.vertical, 10)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(key.accessibilityLabel)
                            .disabled(!client.isReady || client.isSendingText)
                        }
                    }
                    Text(client.message).font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }
            .navigationTitle("Keyboard").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.disabled(client.isSendingText)
                }
            }
            .interactiveDismissDisabled(client.isSendingText)
            .onAppear { composing = true }
        }
    }
}
