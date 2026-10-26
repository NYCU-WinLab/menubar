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
            button.title = " " + MenuBarLabel.truncate(title, width: defaults.integer(forKey: Pref.menuBarTitleWidth))
        } else {
            button.title = ""
        }
    }

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

    /// While open, the menu follows the model (a song ends, the door goes
    /// offline) like the system menus do.
    private func trackMenu() {
        guard isOpen else { return }
        withObservationTracking {
            _ = (model.keyState, model.music?.current?.id, model.music?.paused, model.door, model.meeting,
                 model.roomsToday, model.myBookings, model.bentoOrders, model.announcements, model.errors,
                 model.queue.count, model.grantedApps, model.outdated, updater.available)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isOpen else { return }
                self.rebuild()
                self.trackMenu()
            }
        }
    }

    // MARK: - Building

    /// Whether the music queue is unfolded, like Wi-Fi's Other Networks.
    private var queueOpen = false

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
            let enabled = MenuSection.enabled
            for section in MenuSection.allCases where enabled.contains(section) {
                menu.addItem(.separator())
                menu.addItem(view(SectionTitleRow(title: section.title)))
                if !model.grantedApps.contains(section.app) {
                    menu.addItem(note("金鑰沒有開這個權限"))
                } else if let error = model.errors[section] {
                    menu.addItem(note(SectionView.friendly(error)))
                } else {
                    add(section)
                }
            }
        }
        menu.addItem(.separator())
        // Plain items at the bottom, like "Wi-Fi Settings…".
        let settings = ClosureMenuItem(title: "WinLab 設定…") { Self.openSettings() }
        settings.keyEquivalent = ","
        menu.addItem(settings)
        let quit = ClosureMenuItem(title: "結束 WinLab") { NSApp.terminate(nil) }
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func add(_ section: MenuSection) {
        switch section {
        case .music: addMusic()
        case .door: addDoor()
        case .meeting: addMeeting()
        case .rooms: addRooms()
        case .bento: addBento()
        case .bulletin: addBulletin()
        }
    }

    private func addMusic() {
        guard let music = model.music else {
            menu.addItem(note("讀取中…"))
            return
        }
        menu.addItem(view(NowPlayingRow()))
        menu.addItem(view(VolumeRow()))
        menu.addItem(row(
            symbol: music.paused ? "play.fill" : "pause.fill", title: music.paused ? "繼續播放" : "暫停",
            shortcut: .togglePause, closes: false
        ) { [model] in Task { await model.togglePause() } })
        menu.addItem(row(
            symbol: "forward.fill", title: "下一首", enabled: music.current != nil, shortcut: .skip, closes: false
        ) { [model] in Task { await model.skip() } })
        if !model.queue.isEmpty {
            menu.addItem(view(MenuRow(
                title: "接下來 \(model.queue.count) 首",
                action: { [weak self] in
                    guard let self else { return }
                    self.queueOpen.toggle()
                    self.rebuild()
                }
            ) {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(queueOpen ? 90 : 0))
            }))
            if queueOpen {
                for song in model.queue.prefix(10) {
                    menu.addItem(view(MenuRow(
                        symbol: "music.note", title: song.track.title,
                        subtitle: [song.track.artist, song.addedBy.map { "\($0) 點的" }].compactMap { $0 }.joined(separator: "，")
                    )))
                }
            }
        }
        menu.addItem(row(symbol: "plus", title: "點歌") { [model] in model.openPortal("music") })
    }

    private func addDoor() {
        let door = model.door
        let online = door?.online == true
        menu.addItem(row(
            symbol: "door.left.hand.open", title: "開門",
            subtitle: online ? "門禁在線" : (door?.configured == false ? "門禁未設定" : "門禁離線"),
            enabled: online, shortcut: .openDoor
        ) { [model] in Task { await model.openDoor() } })
    }

    private func addMeeting() {
        guard let meeting = model.meeting else {
            menu.addItem(note("還沒排下一次週會"))
            return
        }
        if meeting.kind == .holiday {
            menu.addItem(note("\(meeting.date) 放假\(meeting.holiday.map { "，\($0)" } ?? "")"))
            return
        }
        let when = model.meetingStart?.formatted(MeetingFormat.when) ?? "\(meeting.date) \(meeting.startsAt)"
        var detail: [String] = []
        if let presenter = meeting.presenter?.name { detail.append("\(presenter) 報告") }
        detail.append(meeting.location)
        menu.addItem(row(symbol: "person.3.fill", title: when, subtitle: detail.joined(separator: "，")) { [model] in
            model.openPortal("meetings")
        })
        if let join = meeting.joinUrl.flatMap(URL.init(string:)) {
            menu.addItem(row(symbol: "video.fill", title: "加入 Teams", active: true) { NSWorkspace.shared.open(join) })
        }
        if let slides = meeting.slidesUrl.flatMap(URL.init(string:)) {
            menu.addItem(row(symbol: "doc.richtext", title: "投影片") { NSWorkspace.shared.open(slides) })
        }
    }

    private func addRooms() {
        let now = AppModel.nowHHMM()
        let runs = (model.roomsToday?.runs ?? []).filter { $0.end > now && $0.tier != .full }.prefix(4)
        if runs.isEmpty { menu.addItem(note("今天沒有可借的時段了")) }
        for run in runs {
            let rooms: String = switch run.tier {
            case .free: run.freeRooms.joined(separator: "、")
            case .lab: "實驗室：" + run.labRooms.joined(separator: "、")
            case .paid: "付費：" + run.paidRooms.joined(separator: "、")
            case .full, .unknown: "都滿了"
            }
            menu.addItem(row(
                symbol: "clock", title: "\(run.start) 到 \(run.end)", subtitle: rooms, active: run.tier == .free
            ) { [model] in model.openPortal("meetings") })
        }
        for booking in model.myBookings.prefix(3) {
            let join = booking.meeting?.joinUrl.flatMap(URL.init(string:))
            menu.addItem(row(
                symbol: join != nil ? "video.fill" : "calendar", title: booking.title,
                subtitle: "\(booking.date.suffix(5)) \(booking.startTime)\(booking.room.map { "，\($0)" } ?? "")"
            ) { [model] in
                if let join { NSWorkspace.shared.open(join) } else { model.openPortal("meetings") }
            })
        }
        menu.addItem(row(symbol: "plus", title: "借會議室") { [model] in model.openPortal("meetings") })
    }

    private func addBento() {
        if model.bentoOrders.isEmpty {
            menu.addItem(note("目前沒有開單"))
            return
        }
        for order in model.bentoOrders {
            let mine = model.myLines(in: order.id)
            let detail = mine.isEmpty
                ? "\(Int(order.people)) 人點了 \(Int(order.dishes)) 份"
                : "我點了 \(mine.map(\.name).joined(separator: "、"))"
            menu.addItem(row(
                symbol: "takeoutbag.and.cup.and.straw.fill", title: order.restaurant, subtitle: detail,
                active: !mine.isEmpty, enabled: model.bentoDetail[order.id] != nil
            ) { [weak self] in self?.openBento?(order.id) })
        }
    }

    private func addBulletin() {
        if model.announcements.isEmpty {
            menu.addItem(note("沒有公告"))
            return
        }
        for a in model.announcements.prefix(3) {
            menu.addItem(row(
                symbol: "megaphone.fill", title: a.title,
                subtitle: [a.author, a.createdAt.formatted(.relative(presentation: .named))].compactMap { $0 }.joined(separator: "，")
            ) { [model] in model.openPortal("bulletin") })
        }
    }

    // MARK: - Items

    /// A MenuRow. Choosing it closes the menu first, unless closes is false
    /// (pause and skip keep it open, as the system Now Playing does).
    private func row(
        symbol: String, title: String, subtitle: String? = nil, active: Bool = false, enabled: Bool = true,
        shortcut: HotkeyAction? = nil, closes: Bool = true, _ run: @escaping @MainActor () -> Void
    ) -> NSMenuItem {
        let menu = self.menu
        let keys = shortcut.flatMap { Hotkeys.shared.shortcuts[$0]?.display }
        return view(MenuRow(
            symbol: symbol, title: title, subtitle: subtitle, active: active, enabled: enabled,
            action: {
                if closes { menu.cancelTracking() }
                run()
            }
        ) {
            if let keys { Text(keys) }
        })
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

    private func view(_ content: some View) -> NSMenuItem {
        let item = NSMenuItem()
        let host = NSHostingView(rootView: content.environment(model).environment(updater))
        host.frame.size = host.fittingSize
        item.view = host
        return item
    }

    static func openSettings() {
        NSApp.activate()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
