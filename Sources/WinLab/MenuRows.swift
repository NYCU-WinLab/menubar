import PortalKit
import SwiftUI

/// Rows inside the native menu, measured from the system Wi-Fi, Sound and
/// Battery menus (in points): 13 inset, 32 row height, 26 icon circle, 8 gap
/// from icon to text, 13 pt text, section titles 13 pt semibold secondary.
enum MenuMetrics {
    static let width: CGFloat = 308
    static let inset: CGFloat = 13
    static let rowHeight: CGFloat = 32
    static let icon: CGFloat = 26
    static let gap: CGFloat = 8
    /// The hover highlight sits this far inside the menu edge.
    static let highlightInset: CGFloat = 5
}

/// "WinLab" with who is signed in, like the title row of the Wi-Fi menu.
struct HeaderRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            Text("WinLab").fontWeight(.bold)
            Spacer()
            if let me = model.me {
                Text(me.name).foregroundStyle(.secondary)
            }
            if model.keyState == .ok {
                Circle()
                    .fill(model.connected ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                    .help(model.connected ? "即時更新中" : "重新連線中")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, MenuMetrics.inset)
        .frame(width: MenuMetrics.width, height: 40, alignment: .leading)
    }
}

/// A section title: "Known Networks" in the Wi-Fi menu.
struct SectionTitleRow: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, MenuMetrics.inset)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .frame(width: MenuMetrics.width, alignment: .leading)
    }
}

/// A row with a round icon, a title, an optional subtitle and trailing
/// detail, like the rows of the Wi-Fi menu. MenuItemView draws its hover
/// highlight from the menu's own highlight state and handles the click.
struct MenuRow<Trailing: View>: View {
    var symbol: String?
    let title: String
    var subtitle: String?
    /// Fills the icon circle with the accent color (the joined network).
    var active = false
    var enabled = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: MenuMetrics.gap) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(active ? .white : .primary)
                    .frame(width: MenuMetrics.icon, height: MenuMetrics.icon)
                    .background(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.secondary), in: .circle)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            trailing
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .opacity(enabled ? 1 : 0.4)
        .padding(.horizontal, MenuMetrics.inset)
        .frame(width: MenuMetrics.width, alignment: .leading)
        .frame(minHeight: subtitle == nil ? MenuMetrics.rowHeight : 40)
    }
}

extension MenuRow where Trailing == EmptyView {
    init(symbol: String? = nil, title: String, subtitle: String? = nil, active: Bool = false, enabled: Bool = true) {
        self.init(symbol: symbol, title: title, subtitle: subtitle, active: active, enabled: enabled, trailing: { EmptyView() })
    }
}

/// Pause, next, volume and request a song, in one row.
struct MusicControlsRow: View {
    @Environment(AppModel.self) private var model
    @State private var volume: Double?

    var body: some View {
        let music = model.music
        HStack(spacing: 8) {
            control(music?.paused == true ? "play.fill" : "pause.fill", help: music?.paused == true ? "繼續" : "暫停", shortcut: .togglePause) {
                Task { await model.togglePause() }
            }
            control("forward.fill", help: "下一首", shortcut: .skip) {
                Task { await model.skip() }
            }
            .disabled(music?.current == nil)
            Image(systemName: "speaker.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
            Slider(
                value: Binding(get: { volume ?? music?.volume ?? 0 }, set: { volume = $0 }),
                in: 0 ... 100
            ) { editing in
                guard !editing, let v = volume else { return }
                Task {
                    await model.setVolume(Int(v.rounded()))
                    volume = nil
                }
            }
            .controlSize(.small)
            .help("音量 \(Int((volume ?? music?.volume ?? 0).rounded()))")
            control("plus", help: "點歌") { model.openPortal("music") }
        }
        .padding(.horizontal, MenuMetrics.inset)
        .frame(width: MenuMetrics.width, height: MenuMetrics.rowHeight + 4)
    }

    private func control(_ symbol: String, help: String, shortcut: HotkeyAction? = nil, _ run: @escaping () -> Void) -> some View {
        let keys = shortcut.flatMap { Hotkeys.shared.shortcuts[$0]?.display }
        return Button(action: run) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: MenuMetrics.icon, height: MenuMetrics.icon)
                .background(.fill.secondary, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(keys.map { "\(help)（\($0)）" } ?? help)
    }
}

/// The next songs, as quiet lines under the controls.
struct QueueRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title).lineLimit(1)
            Text(detail).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .padding(.horizontal, MenuMetrics.inset)
        .frame(width: MenuMetrics.width, height: 22, alignment: .leading)
    }
}

/// The song playing in the lab, with its progress.
struct NowPlayingRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let music = model.music, let current = music.current {
                HStack(spacing: 10) {
                    AsyncImage(url: current.track.thumbnail.flatMap(URL.init(string:)).map(Self.larger)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: "music.note").foregroundStyle(.secondary)
                    }
                    .frame(width: 44, height: 44)
                    .background(.fill.tertiary)
                    .clipShape(.rect(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.track.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text([current.track.artist, current.addedBy.map { "\($0) 點的" }].compactMap { $0 }.joined(separator: "，"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if let duration = current.track.durationS, duration > 0 {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let position = model.position(at: context.date)
                        HStack(spacing: 8) {
                            Text(clock(position))
                            ProgressView(value: min(position, duration), total: duration)
                                .progressViewStyle(.linear)
                                .controlSize(.mini)
                            Text(clock(duration))
                        }
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
                if !music.online {
                    Label("實驗室的播放器離線", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("沒有在播").font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, MenuMetrics.inset)
        .padding(.vertical, 6)
        .frame(width: MenuMetrics.width, alignment: .leading)
    }

    private func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// YouTube Music thumbnails come at 60 px; ask for 120 for Retina.
    static func larger(_ url: URL) -> URL {
        URL(string: url.absoluteString.replacingOccurrences(of: "=w60-h60", with: "=w120-h120")) ?? url
    }
}

/// The menu bar title helpers.
enum MenuBarLabel {
    /// The WinLab mascot, drawn in the menu bar's color (bundled app only).
    static let mascot: NSImage? = {
        let image = Bundle.main.image(forResource: "MenuIcon")
        image?.isTemplate = true
        return image
    }()

    /// Cuts a title to about this many points (7 per Latin character, 13 per
    /// CJK one), so a long song does not push other menu bar items away.
    static func truncate(_ text: String, width: Int) -> String {
        var used = 0.0
        var out = ""
        for ch in text {
            used += ch.unicodeScalars.first.map { $0.value > 0x2E80 ? 13 : 7 } ?? 7
            if used > Double(width) { return out.trimmingCharacters(in: .whitespaces) + "…" }
            out.append(ch)
        }
        return out
    }
}

enum SectionView {
    /// Server-side failures read as a sentence, not a stack trace.
    static func friendly(_ error: String) -> String {
        if error.localizedCaseInsensitiveContains("fetch failed") { return "portal 暫時讀不到這項資料" }
        return error
    }
}
