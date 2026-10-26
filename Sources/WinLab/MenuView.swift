import PortalKit
import SwiftUI

/// The window under the menu bar item.
struct MenuView: View {
    @Environment(AppModel.self) private var model
    @Environment(Updater.self) private var updater
    @AppStorage(Pref.sections) private var sectionsRaw: String = MenuSection.store(Set(MenuSection.allCases))

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.outdated || updater.available != nil {
                UpdateBanner()
                Divider()
            }
            content
            if let toast = model.toast {
                Divider()
                Text(toast)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.quaternary.opacity(0.5))
            }
        }
        .frame(width: 340)
        .animation(.default, value: model.toast)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Group {
                if let mascot = MenuBarLabel.mascot {
                    Image(nsImage: mascot).resizable().frame(width: 20, height: 20)
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                }
            }
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text("WinLab").font(.headline)
                if let me = model.me {
                    Text(me.name).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.keyState == .ok {
                Circle()
                    .fill(model.connected ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                    .help(model.connected ? "即時更新中" : "重新連線中")
            }
            Button {
                model.openPortal()
            } label: {
                Image(systemName: "safari")
            }
            .buttonStyle(.borderless)
            .help("開啟 portal")
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("設定")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("結束 WinLab")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch model.keyState {
        case .missing, .invalid:
            KeySetupView()
                .padding(14)
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
            VStack(alignment: .leading, spacing: 0) {
                ForEach(MenuSection.allCases.filter { enabled.contains($0) }) { section in
                    SectionView(section: section)
                    if section != MenuSection.allCases.last(where: { enabled.contains($0) }) {
                        Divider().padding(.leading, 14)
                    }
                }
            }
        }
        .frame(maxHeight: 620)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One part of the menu, or why it is empty.
struct SectionView: View {
    let section: MenuSection
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(section.title, systemImage: section.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if !model.grantedApps.contains(section.app) {
                Text("金鑰沒有開「\(section.app)」權限")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let error = model.errors[section] {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else {
                switch section {
                case .music: MusicSection()
                case .door: DoorSection()
                case .meeting: MeetingSection()
                case .rooms: RoomsSection()
                case .bento: BentoSection()
                case .bulletin: BulletinSection()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Shown when this build is behind the portal, or Sparkle found a release.
struct UpdateBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(Updater.self) private var updater

    var body: some View {
        HStack {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
            Text(updater.available.map { "WinLab \($0) 可以更新了" } ?? "portal 已更新，請更新 WinLab")
                .font(.callout)
            Spacer()
            Button("更新") { updater.checkForUpdates() }
                .controlSize(.small)
                .disabled(!updater.canCheck)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// Paste an API key without leaving the menu.
struct KeySetupView: View {
    @Environment(AppModel.self) private var model
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if case let .invalid(message) = model.keyState {
                Text(message).font(.callout).foregroundStyle(.red)
            } else {
                Text("貼上 portal 的 API 金鑰就能開始用。").font(.callout)
            }
            Text("在 portal 的 API 金鑰頁建立一把，勾選個人資料、點歌、開門、會議、便當、公告。")
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField("wak_…", text: $key)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Button("建立金鑰") { model.openPortal("api-keys") }
                Spacer()
                Button("儲存", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func save() {
        let value = key
        key = ""
        Task { await model.saveKey(value) }
    }
}
