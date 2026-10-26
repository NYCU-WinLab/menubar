import AppKit
import ServiceManagement
import SwiftUI

/// Settings: one page, only what people choose themselves. Everything else
/// is a fixed choice (see Pref).
@MainActor
enum SettingsWindow {
    static func controller(model: AppModel, updater: Updater) -> NSViewController {
        let host = NSHostingController(rootView: SettingsView().environment(model).environment(updater))
        host.sizingOptions = .preferredContentSize
        return host
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Updater.self) private var updater
    @AppStorage(Pref.menuBarText) private var menuBarText = MenuBarText.lyrics.rawValue
    @AppStorage(Pref.notify) private var notify = true
    @State private var key = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var shortcuts = Hotkeys.shared.shortcuts
    @State private var conflicts = Hotkeys.shared.conflicts

    var body: some View {
        Form {
            Section {
                LabeledContent("狀態") { status }
                SecureField("API 金鑰", text: $key, prompt: Text("貼上新的金鑰"))
                    .onSubmit(save)
            } header: {
                Text("portal")
            } footer: {
                HStack {
                    Button("在 portal 建立金鑰") { model.openPortal("api-keys") }
                        .buttonStyle(.link)
                    Spacer()
                    Button("儲存", action: save)
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("一般") {
                Toggle("登入時開啟", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                Picker("選單列顯示", selection: $menuBarText) {
                    ForEach(MenuBarText.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("通知公告、便當開單和週會提醒", isOn: $notify)
            }

            Section {
                ForEach(HotkeyAction.allCases) { action in
                    LabeledContent(action.title) {
                        HStack(spacing: 6) {
                            if conflicts.contains(action) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .help("其他 app 已經用了這組快捷鍵")
                            }
                            ShortcutRecorder(shortcut: shortcuts[action]) { new in
                                Hotkeys.shared.set(new, for: action)
                                shortcuts = Hotkeys.shared.shortcuts
                                conflicts = Hotkeys.shared.conflicts
                            }
                        }
                    }
                }
            } header: {
                Text("快捷鍵")
            } footer: {
                Text("在任何 app 都能用。要含 ⌘、⌥ 或 ⌃；F1 到 F20 可以單獨用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("版本", value: Self.version)
            } footer: {
                HStack {
                    Spacer()
                    Button("檢查更新") { updater.checkForUpdates() }
                        .disabled(!updater.canCheck)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { NSApp.activate() }
    }

    @ViewBuilder
    private var status: some View {
        switch model.keyState {
        case .missing: Text("還沒設定").foregroundStyle(.secondary)
        case .checking: ProgressView().controlSize(.small)
        case .ok: Text(model.me.map { "已連線：\($0.name)" } ?? "已連線").foregroundStyle(.green)
        case let .invalid(message): Text(message).foregroundStyle(.red)
        }
    }

    /// Saving replaces the key in the keychain; a revoked key is replaced the
    /// same way, so there is no separate remove button.
    private func save() {
        let value = key
        key = ""
        Task { await model.saveKey(value) }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}

struct ShortcutRecorder: View {
    let shortcut: Shortcut?
    let onChange: (Shortcut?) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "請按組合鍵" : (shortcut?.display ?? "未設定"))
                .monospaced()
                .frame(minWidth: 110)
                .foregroundStyle(shortcut == nil && !recording ? .secondary : .primary)
        }
        .tint(recording ? .accentColor : nil)
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        Hotkeys.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case 53: // escape
                stop()
            case 51, 117: // delete
                onChange(nil)
                stop()
            default:
                guard let s = Shortcut(event: event) else {
                    NSSound.beep()
                    return nil
                }
                onChange(s)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { Hotkeys.shared.registerAll() }
        recording = false
    }
}
