import AppKit
import Carbon.HIToolbox
import Observation
import PortalKit
import SwiftUI

/// The menu bar item and its menu: a native NSMenu, as the HIG asks of menu
/// bar extras, so the system draws the glass, corners, type and highlight.
/// Only the now-playing row and the volume slider are custom views, the way
/// the system Sound menu does it.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let updater: Updater
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var isOpen = false
    var openBento: ((String) -> Void)?

    init(model: AppModel, updater: Updater) {
        self.model = model
        self.updater = updater
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        item.button?.imagePosition = .imageLeading
        trackLabel()
    }

    /// Opens the menu (development screenshots, and the hotkey).
    func open() {
        item.button?.performClick(nil)
    }

    // MARK: - Menu bar label

    private func trackLabel() {
        withObservationTracking {
            updateLabel()
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackLabel() }
        }
    }

    private func updateLabel() {
        guard let button = item.button else { return }
        let music = model.music
        let playing = music?.current != nil && music?.paused == false && music?.state == .playing
        let defaults = UserDefaults.standard
        if playing {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "播放中")
        } else {
            button.image = MenuBarLabel.mascot ?? NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: "WinLab")
        }
        if playing, defaults.bool(forKey: Pref.showTitleInMenuBar), let title = music?.current?.track.title {
            button.title = " " + MenuBarLabel.truncate(title, width: Pref.titleWidth)
        } else {
            button.title = ""
        }
    }

    // MARK: - NSMenuDelegate

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isOpen = true
        trackMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        isOpen = false
    }

    /// While open, the menu follows the model (a song ends, an order opens)
    /// like the system menus do.
    private func trackMenu() {
        guard isOpen else { return }
        withObservationTracking {
            _ = (model.keyState, model.music?.current?.id, model.music?.paused, model.queue.count, model.door,
                 model.meeting, model.myBookings, model.bentoOrders, model.bentoDetail.count, model.announcements,
                 model.errors, model.grantedApps, model.outdated, updater.available)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isOpen else { return }
                self.rebuild()
                self.trackMenu()
            }
        }
    }

    // MARK: - Building

    /// Songs listed under the controls.
    private static let queueLimit = 3
    /// Announcements newer than this show up.
    private static let recentAnnouncement: TimeInterval = 7 * 86400

    private func rebuild() {
        menu.removeAllItems()
        menu.addItem(view(HeaderRow()))
        if model.outdated || updater.available != nil {
            menu.addItem(row(
                symbol: "arrow.down", title: updater.available.map { "更新到 WinLab \($0)" } ?? "portal 已改版，請更新",
                active: true
            ) { [updater] in updater.checkForUpdates() })
        }
        switch model.keyState {
        case .missing, .invalid:
            menu.addItem(.separator())
            if case let .invalid(message) = model.keyState { menu.addItem(note(message)) }
            menu.addItem(row(symbol: "key.fill", title: "設定 API 金鑰") { Self.openSettings() })
            menu.addItem(row(symbol: "safari", title: "在 portal 建立金鑰") { [model] in model.openPortal("api-keys") })
        case .checking:
            menu.addItem(.separator())
            menu.addItem(note("連線中…"))
        case .ok:
            for section in MenuSection.allCases {
                let items = items(for: section)
                // Dynamic sections leave the menu when they have nothing to say.
                guard !items.isEmpty else { continue }
                menu.addItem(.separator())
                menu.addItem(view(SectionTitleRow(title: section.title)))
                items.forEach(menu.addItem)
            }
        }
        menu.addItem(.separator())
        // Plain items at the bottom, like "Wi-Fi Settings…".
        let settings = ClosureMenuItem(title: "設定…") { Self.openSettings() }
        settings.keyEquivalent = ","
        menu.addItem(settings)
        let quit = ClosureMenuItem(title: "結束") { NSApp.terminate(nil) }
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func items(for section: MenuSection) -> [NSMenuItem] {
        guard model.grantedApps.contains(section.app) else {
            // Music and the door are always there; say why they are empty.
            return section == .music || section == .door ? [note("金鑰沒有開這個權限")] : []
        }
        if let error = model.errors[section] {
            return section == .rooms || section == .bulletin ? [] : [note(SectionView.friendly(error))]
        }
        switch section {
        case .music: return musicItems()
        case .door: return doorItems()
        case .meeting: return meetingItems()
        case .rooms: return roomItems()
        case .bento: return bentoItems()
        case .bulletin: return bulletinItems()
        }
    }

    private func musicItems() -> [NSMenuItem] {
        guard model.music != nil else { return [note("讀取中…")] }
        var items = [view(NowPlayingRow()), view(MusicControlsRow())]
        for song in model.queue.prefix(Self.queueLimit) {
            items.append(view(QueueRow(title: song.track.title, detail: song.track.artist)))
        }
        if model.queue.count > Self.queueLimit {
            items.append(view(QueueRow(title: "", detail: "還有 \(model.queue.count - Self.queueLimit) 首")))
        }
        return items
    }

    private func doorItems() -> [NSMenuItem] {
        let door = model.door
        let online = door?.online == true
        return [row(
            symbol: "door.left.hand.open", title: "開門",
            subtitle: online ? "門禁在線" : (door?.configured == false ? "門禁未設定" : "門禁離線"),
            enabled: online, shortcut: .openDoor
        ) { [model] in Task { await model.openDoor() } }]
    }

    private func meetingItems() -> [NSMenuItem] {
        guard let meeting = model.meeting else { return [note("還沒排下一次週會")] }
        if meeting.kind == .holiday {
            return [note("\(meeting.date) 放假\(meeting.holiday.map { "，\($0)" } ?? "")")]
        }
        let when = model.meetingStart?.formatted(MeetingFormat.when) ?? "\(meeting.date) \(meeting.startsAt)"
        var detail: [String] = []
        if let presenter = meeting.presenter?.name { detail.append("\(presenter) 報告") }
        detail.append(meeting.location)
        var items = [row(symbol: "person.3.fill", title: when, subtitle: detail.joined(separator: "，")) { [model] in
            model.openPortal("meetings")
        }]
        if let join = meeting.joinUrl.flatMap(URL.init(string:)) {
            items.append(row(symbol: "video.fill", title: "加入 Teams", active: true) { NSWorkspace.shared.open(join) })
        }
        return items
    }

    /// My meetings that have not ended, today through the next two days.
    private func roomItems() -> [NSMenuItem] {
        let today = AppModel.today()
        let now = AppModel.nowHHMM()
        let upcoming = model.myBookings
            .filter { $0.date > today || ($0.date == today && $0.endTime > now) }
            .sorted { ($0.date, $0.startTime) < ($1.date, $1.startTime) }
        return upcoming.prefix(3).map { booking in
            let join = booking.meeting?.joinUrl.flatMap(URL.init(string:))
            let day = booking.date == today ? "今天" : String(booking.date.suffix(5))
            return row(
                symbol: join != nil ? "video.fill" : "calendar", title: booking.title,
                subtitle: "\(day) \(booking.startTime)\(booking.room.map { "，\($0)" } ?? "")",
                active: join != nil
            ) { [model] in
                if let join { NSWorkspace.shared.open(join) } else { model.openPortal("meetings") }
            }
        }
    }

    /// Open orders I have not ordered from yet.
    private func bentoItems() -> [NSMenuItem] {
        model.bentoOrders
            .filter { model.bentoDetail[$0.id] != nil && model.myLines(in: $0.id).isEmpty }
            .map { order in
                row(
                    symbol: "takeoutbag.and.cup.and.straw.fill", title: order.restaurant,
                    subtitle: "\(Int(order.people)) 人點了，按一下點餐", active: true
                ) { [weak self] in self?.openBento?(order.id) }
            }
    }

    private func bulletinItems() -> [NSMenuItem] {
        let since = Date().addingTimeInterval(-Self.recentAnnouncement)
        return model.announcements.filter { $0.createdAt > since }.prefix(3).map { a in
            row(
                symbol: "megaphone.fill", title: a.title,
                subtitle: [a.author, a.createdAt.formatted(.relative(presentation: .named))].compactMap { $0 }.joined(separator: "，")
            ) { [model] in model.openPortal("bulletin") }
        }
    }

    // MARK: - Items

    /// A MenuRow that runs `run` when chosen; the menu closes first.
    private func row(
        symbol: String, title: String, subtitle: String? = nil, active: Bool = false, enabled: Bool = true,
        shortcut: HotkeyAction? = nil, _ run: @escaping @MainActor () -> Void
    ) -> NSMenuItem {
        let keys = shortcut.flatMap { Hotkeys.shared.shortcuts[$0]?.display }
        let item = view(MenuRow(symbol: symbol, title: title, subtitle: subtitle, active: active, enabled: enabled) {
            if let keys { Text(keys) }
        }, action: enabled ? run : nil)
        item.isEnabled = enabled
        return item
    }

    /// A line of secondary text, at the row inset.
    private func note(_ text: String) -> NSMenuItem {
        view(
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, MenuMetrics.inset)
                .frame(width: MenuMetrics.width, height: MenuMetrics.rowHeight, alignment: .leading)
        )
    }

    private func view(_ content: some View, action: (@MainActor () -> Void)? = nil) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = MenuItemView(content.environment(model).environment(updater), action: action)
        return item
    }

    // MARK: - Settings

    private static var settingsWindow: NSWindow?
    static var makeSettings: (() -> NSViewController)?

    /// Our own window: a menu bar app has no Settings menu to route
    /// showSettingsWindow: through.
    static func openSettings() {
        if settingsWindow == nil, let controller = makeSettings?() {
            let window = NSWindow(contentViewController: controller)
            window.title = "WinLab 設定"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

/// Hosts a SwiftUI row in the menu. Rows with an action draw the menu's own
/// highlight (a rounded fill, inset like the system menus) and run the
/// action on click; rows without one pass events to their controls.
@MainActor
final class MenuItemView: NSView {
    private let action: (@MainActor () -> Void)?

    init(_ content: some View, action: (@MainActor () -> Void)?) {
        self.action = action
        let host = NSHostingView(rootView: content)
        let size = host.fittingSize
        super.init(frame: NSRect(origin: .zero, size: size))
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard action != nil, enclosingMenuItem?.isHighlighted == true, enclosingMenuItem?.isEnabled == true else { return }
        let rect = bounds.insetBy(dx: MenuMetrics.highlightInset, dy: 0)
        NSColor.labelColor.withAlphaComponent(0.1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsDisplay = true
    }

    /// Action rows take the click themselves; control rows let it through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard action != nil else { return super.hitTest(point) }
        return frame.contains(point) ? self : nil
    }

    override func mouseUp(with event: NSEvent) {
        guard let action, enclosingMenuItem?.isEnabled == true else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        action()
    }
}

/// A menu item that runs a closure.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let run: @MainActor () -> Void

    init(title: String, run: @escaping @MainActor () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() {
        run()
    }
}

enum MeetingFormat {
    static let when: Date.FormatStyle = Date.FormatStyle(
        date: .omitted, time: .omitted, locale: Locale(identifier: "zh-Hant-TW"), timeZone: TimeZone(identifier: "Asia/Taipei")!
    ).month(.defaultDigits).day().weekday(.abbreviated).hour().minute()
}

extension Shortcut {
    /// The menu key equivalent for this shortcut, when it has one.
    var keyEquivalent: String? {
        let special: [Int: Int] = [
            kVK_LeftArrow: NSLeftArrowFunctionKey, kVK_RightArrow: NSRightArrowFunctionKey,
            kVK_UpArrow: NSUpArrowFunctionKey, kVK_DownArrow: NSDownArrowFunctionKey,
            kVK_F1: NSF1FunctionKey, kVK_F2: NSF2FunctionKey, kVK_F3: NSF3FunctionKey, kVK_F4: NSF4FunctionKey,
            kVK_F5: NSF5FunctionKey, kVK_F6: NSF6FunctionKey, kVK_F7: NSF7FunctionKey, kVK_F8: NSF8FunctionKey,
        ]
        if let f = special[Int(keyCode)], let scalar = UnicodeScalar(f) { return String(Character(scalar)) }
        if keyCode == UInt32(kVK_Space) { return " " }
        let name = Self.keyName(Int(keyCode))
        return name.count == 1 ? name.lowercased() : nil
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }
}
