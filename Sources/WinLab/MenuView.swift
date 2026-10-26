import PortalKit
import SwiftUI

/// The window under the menu bar item. The window itself is system Liquid
/// Glass; modules sit on it as content, controls use glass button styles.
struct MenuView: View {
    @Environment(AppModel.self) private var model
    @Environment(Updater.self) private var updater
    @AppStorage(Pref.sections) private var sectionsRaw: String = MenuSection.store(Set(MenuSection.allCases))

    var body: some View {
        VStack(spacing: Metrics.moduleSpacing) {
            header
            if model.outdated || updater.available != nil {
                UpdateBanner()
            }
            content
        }
        .padding(Metrics.inset)
        .frame(width: Metrics.windowWidth)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassCapsule()
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: model.toast)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Group {
                if let mascot = MenuBarLabel.mascot {
                    Image(nsImage: mascot).resizable().scaledToFit()
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                }
            }
            .frame(width: 22, height: 22)
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text("WinLab").font(.headline)
                if let me = model.me {
                    HStack(spacing: 4) {
                        Text(me.name)
                        if model.keyState == .ok {
                            Circle()
                                .fill(model.connected ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                                .help(model.connected ? "即時更新中" : "重新連線中")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                Button("開啟 portal") { model.openPortal() }
                SettingsLink { Text("設定…") }
                    .keyboardShortcut(",")
                Divider()
                Button("結束 WinLab") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 16, height: 16)
            }
            .menuIndicator(.hidden)
            .menuStyle(.button)
            .circleButton()
            .fixedSize()
            .help("更多")
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var content: some View {
        switch model.keyState {
        case .missing, .invalid:
            KeySetupView()
        case .checking:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(24)
        case .ok:
            if let orderId = model.openBentoOrder {
                BentoOrderView(orderId: orderId)
            } else {
                sections
            }
        }
    }

    private var sections: some View {
        let enabled = MenuSection.parse(sectionsRaw)
        return ScrollView {
            VStack(spacing: Metrics.moduleSpacing) {
                ForEach(MenuSection.allCases.filter { enabled.contains($0) }) { section in
                    SectionView(section: section)
                }
            }
        }
        .scrollIndicators(.never)
        .frame(maxHeight: 640)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(.rect(cornerRadius: Metrics.moduleRadius, style: .continuous))
    }
}

/// One module, or why it is empty.
struct SectionView: View {
    let section: MenuSection
    @Environment(AppModel.self) private var model

    var body: some View {
        switch section {
        case .music: module { MusicSection() }
        case .door: module { DoorSection() }
        case .meeting: module { MeetingSection() }
        case .rooms: module { RoomsSection() }
        case .bento: module { BentoSection() }
        case .bulletin: module { BulletinSection() }
        }
    }

    private func module(@ViewBuilder _ content: () -> some View) -> some View {
        Module(title: section.title, symbol: section.symbol) {
            if !model.grantedApps.contains(section.app) {
                Notice(text: "金鑰沒有開這個權限", symbol: "lock")
            } else if let error = model.errors[section] {
                Notice(text: Self.friendly(error), symbol: "exclamationmark.triangle")
            } else {
                content()
            }
        }
    }

    /// Server-side failures read as a sentence, not a stack trace.
    static func friendly(_ error: String) -> String {
        if error.localizedCaseInsensitiveContains("fetch failed") { return "portal 暫時讀不到這項資料" }
        return error
    }
}

/// Shown when this build is behind the portal, or Sparkle found a release.
struct UpdateBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(Updater.self) private var updater

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
            Text(updater.available.map { "WinLab \($0) 可以更新了" } ?? "portal 已改版，請更新 WinLab")
                .font(.callout)
            Spacer()
            Button("更新") { updater.checkForUpdates() }
                .glassButton(prominent: true)
                .controlSize(.small)
                .disabled(!updater.canCheck)
        }
        .padding(Metrics.modulePadding)
        .background(.fill.quaternary, in: .rect(cornerRadius: Metrics.moduleRadius, style: .continuous))
    }
}

/// Paste an API key without leaving the menu.
struct KeySetupView: View {
    @Environment(AppModel.self) private var model
    @State private var key = ""

    var body: some View {
        Module(title: "連上 portal", symbol: "key") {
            VStack(alignment: .leading, spacing: 10) {
                if case let .invalid(message) = model.keyState {
                    Notice(text: message, symbol: "exclamationmark.triangle")
                } else {
                    Text("貼上 portal 的 API 金鑰就能開始用。").font(.callout)
                }
                Text("建立金鑰時勾選個人資料、點歌、開門、會議、便當、公告。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("wak_…", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                HStack {
                    Button("建立金鑰") { model.openPortal("api-keys") }
                        .glassButton()
                    Spacer()
                    Button("儲存", action: save)
                        .glassButton(prominent: true)
                        .keyboardShortcut(.defaultAction)
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let value = key
        key = ""
        Task { await model.saveKey(value) }
    }
}
