import AppKit
import PortalKit
import ServiceManagement
import SwiftUI

/// The settings window: toolbar tabs, as in system apps. Each tab is a
/// grouped Form at a fixed height, so the window sizes to it.
@MainActor
enum SettingsWindow {
    struct Tab {
        let title: String
        let symbol: String
        let height: CGFloat
        let view: AnyView
    }

    static func tabs() -> [Tab] {
        [
            Tab(title: "帳號", symbol: "person.crop.circle", height: 380, view: AnyView(AccountTab())),
            Tab(title: "顯示", symbol: "menubar.rectangle", height: 470, view: AnyView(DisplayTab())),
            Tab(title: "通知", symbol: "bell.badge", height: 330, view: AnyView(NotificationsTab())),
            Tab(title: "快捷鍵", symbol: "command", height: 420, view: AnyView(ShortcutsTab())),
            Tab(title: "更新", symbol: "arrow.down.circle", height: 330, view: AnyView(UpdatesTab())),
        ]
    }

    @MainActor
    static func controller(model: AppModel, updater: Updater) -> NSViewController {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = false
        for tab in self.tabs() {
            let host = NSHostingController(
                rootView: tab.view
                    .frame(width: 520, height: tab.height)
                    .environment(model)
                    .environment(updater)
            )
            host.sizingOptions = .preferredContentSize
            let item = NSTabViewItem(viewController: host)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            tabs.addTabViewItem(item)
        }
        return tabs
    }
}

// MARK: - Account

private struct AccountTab: View {
    @Environment(AppModel.self) private var model
    @State private var key = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("portal API 金鑰") {
                LabeledContent("狀態") { status }
                SecureField("新的金鑰", text: $key, prompt: Text("wak_…"))
                    .onSubmit(save)
                HStack {
                    Button("在 portal 建立金鑰") { model.openPortal("api-keys") }
                    Spacer()
                    if model.keyState != .missing {
                        Button("移除金鑰", role: .destructive) { model.signOut() }
                    }
                    Button("儲存", action: save)
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("建立金鑰時勾選個人資料、點歌、開門、會議、便當、公告。金鑰存在這台 Mac 的鑰匙圈。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let contract = model.contract, !(contract.missing.isEmpty && contract.changed.isEmpty) {
                Section("API 對齊") {
                    if !contract.missing.isEmpty {
                        LabeledContent("金鑰不能用", value: contract.missing.joined(separator: "、"))
                    }
                    if !contract.changed.isEmpty {
                        LabeledContent("portal 已改版", value: contract.changed.joined(separator: "、"))
                    }
                }
            }
            Section("系統") {
                Toggle("登入時開啟 WinLab", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
            }
        }
        .formStyle(.grouped)
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
}

// MARK: - Display

private struct DisplayTab: View {
    @AppStorage(Pref.showTitleInMenuBar) private var showTitle = true
    @AppStorage(Pref.menuBarTitleWidth) private var width = 160
    @AppStorage(Pref.sections) private var sectionsRaw: String = MenuSection.store(Set(MenuSection.allCases))
    @AppStorage(Pref.confirmDoor) private var confirmDoor = true
    @AppStorage(Pref.volumeStep) private var volumeStep = 5

    var body: some View {
        Form {
            Section("選單列") {
                Toggle("播放中顯示歌名", isOn: $showTitle)
                Picker("歌名最長", selection: $width) {
                    Text("短").tag(100)
                    Text("中").tag(160)
                    Text("長").tag(240)
                }
                .disabled(!showTitle)
            }
            Section("選單內容") {
                ForEach(MenuSection.allCases) { section in
                    Toggle(isOn: binding(section)) {
                        Label(section.title, systemImage: section.symbol)
                    }
                }
            }
            Section("操作") {
                Toggle("開門要按兩次", isOn: $confirmDoor)
                Stepper("音量每次調整 \(volumeStep)", value: $volumeStep, in: 1 ... 20)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(_ section: MenuSection) -> Binding<Bool> {
        Binding {
            MenuSection.parse(sectionsRaw).contains(section)
        } set: { on in
            var set = MenuSection.parse(sectionsRaw)
            if on { set.insert(section) } else { set.remove(section) }
            sectionsRaw = MenuSection.store(set)
        }
    }
}

// MARK: - Notifications

private struct NotificationsTab: View {
    @AppStorage(Pref.notifyAnnouncements) private var announcements = true
    @AppStorage(Pref.notifyMeeting) private var meeting = true
    @AppStorage(Pref.meetingLeadMinutes) private var lead = 10
    @AppStorage(Pref.notifyBento) private var bento = true
    @AppStorage(Pref.notifySong) private var song = false

    var body: some View {
        Form {
            Section {
                Toggle("新公告", isOn: $announcements)
                Toggle("週會提醒", isOn: $meeting)
                Picker("提前", selection: $lead) {
                    ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) 分鐘").tag($0) }
                }
                .disabled(!meeting)
                Toggle("便當開單", isOn: $bento)
                Toggle("換歌", isOn: $song)
            }
            Section {
                Button("打開系統通知設定") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcuts

private struct ShortcutsTab: View {
    @State private var shortcuts = Hotkeys.shared.shortcuts
    @State private var conflicts = Hotkeys.shared.conflicts

    var body: some View {
        Form {
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
                                reload()
                            }
                        }
                    }
                }
            } footer: {
                Text("在任何 app 裡都能用。按下欄位後輸入組合鍵，要含 ⌘、⌥ 或 ⌃；按 ⌫ 清除，按 ⎋ 取消。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("恢復預設") {
                    for action in HotkeyAction.allCases { Hotkeys.shared.set(action.defaultShortcut, for: action) }
                    reload()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func reload() {
        shortcuts = Hotkeys.shared.shortcuts
        conflicts = Hotkeys.shared.conflicts
    }
}

/// A field that records the next key combination.
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

// MARK: - Updates

private struct UpdatesTab: View {
    @Environment(Updater.self) private var updater
    @State private var autoCheck = false
    @State private var autoDownload = false

    var body: some View {
        Form {
            Section {
                LabeledContent("版本", value: Self.version)
                if updater.enabled {
                    Toggle("自動檢查更新", isOn: $autoCheck)
                        .onChange(of: autoCheck) { _, on in updater.automaticallyChecks = on }
                    Toggle("自動下載並安裝", isOn: $autoDownload)
                        .onChange(of: autoDownload) { _, on in updater.automaticallyDownloads = on }
                        .disabled(!autoCheck)
                    if let last = updater.lastCheck {
                        LabeledContent("上次檢查", value: last.formatted(date: .abbreviated, time: .shortened))
                    }
                    Button("立即檢查更新") { updater.checkForUpdates() }
                        .disabled(!updater.canCheck)
                } else {
                    Text("開發版不檢查更新").foregroundStyle(.secondary)
                }
            } footer: {
                Text("更新經過 Apple 公證，並用 WinLab 的金鑰簽章。portal 改版時，WinLab 也會主動找新版。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Link("原始碼與更新紀錄", destination: URL(string: "https://github.com/NYCU-WinLab/menubar/releases")!)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            autoCheck = updater.automaticallyChecks
            autoDownload = updater.automaticallyDownloads
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short)（\($0)）" } ?? short
    }
}
