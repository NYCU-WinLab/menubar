import AppKit
import Foundation
import Observation
import PortalKit

/// Everything the menu shows, kept fresh from the portal: loaded once, then
/// refreshed per app when the change stream says that app changed.
@MainActor
@Observable
final class AppModel {
    /// WINLAB_PORTAL_URL points a development run at a test portal.
    static let portalURL = ProcessInfo.processInfo.environment["WINLAB_PORTAL_URL"]
        .flatMap(URL.init(string:)) ?? URL(string: "https://portal.winlab.tw")!
    static let taipei = TimeZone(identifier: "Asia/Taipei")!

    enum KeyState: Equatable {
        case missing
        case checking
        case ok
        case invalid(String)
    }

    // Account
    private(set) var keyState: KeyState = .missing
    private(set) var me: Whoami.Output?
    /// API apps the key may use (from GET /api/actions).
    private(set) var grantedApps: Set<String> = []
    /// Action name to app, for routing change events.
    private var appOfAction: [String: String] = [:]
    private(set) var contract: ContractStatus?
    /// An answer did not match this build's contract: an update is needed.
    private(set) var outdated = false
    private(set) var connected = false

    // Sections
    private(set) var music: NowPlaying.Output?
    private(set) var musicFetchedAt = Date()
    private(set) var queue: [ListQueue.Output.Item] = []
    private(set) var door: GetDoorStatus.Output?
    private(set) var meeting: GetNextLabMeeting.Output.Meeting?
    private(set) var myBookings: [ListMeetings.Output.Booking] = []
    private(set) var bentoOrders: [ListBentoOrders.Output.Order] = []
    private(set) var bentoDetail: [String: GetBentoOrder.Output] = [:]
    private(set) var announcements: [ListAnnouncements.Output.Announcement] = []
    private(set) var errors: [MenuSection: String] = [:]
    /// A short message after an action (opened the door, ordered).
    private(set) var toast: String?

    let client: PortalClient
    let notifier = Notifier()
    var updater: Updater?

    private var streamTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var pending: Set<String> = []
    private var flushTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    init() {
        client = PortalClient(baseURL: Self.portalURL) { KeyStore.load() }
    }

    // MARK: - Lifecycle

    func start() {
        Pref.registerDefaults()
        Task { await connect() }
    }

    /// Checks the key, loads everything, and listens for changes.
    func connect() async {
        streamTask?.cancel()
        pollTask?.cancel()
        guard KeyStore.load()?.isEmpty == false else {
            keyState = .missing
            clear()
            return
        }
        keyState = .checking
        do {
            me = try await client.run(Whoami.self, .init())
            let remote = try await client.actions()
            grantedApps = Set(remote.compactMap(\.app))
            appOfAction = Dictionary(remote.compactMap { r in r.app.map { (r.name, $0) } }, uniquingKeysWith: { a, _ in a })
            contract = ContractStatus(remote: remote)
            keyState = .ok
            // A changed schema may still decode; look for a build that knows it.
            if contract?.changed.isEmpty == false { updater?.checkInBackground() }
        } catch let error as PortalError {
            switch error {
            case .unauthorized, .noKey, .forbidden: keyState = .invalid(error.localizedDescription)
            case .contract: outdated = true; keyState = .ok
            default: keyState = .invalid(error.localizedDescription)
            }
            if keyState != .ok {
                scheduleRetry()
                return
            }
        } catch {
            keyState = .invalid(error.localizedDescription)
            scheduleRetry()
            return
        }
        await refreshAll(initial: true)
        listen()
        poll()
    }

    func saveKey(_ key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { KeyStore.delete() } else { KeyStore.save(trimmed) }
        await connect()
    }

    func signOut() {
        KeyStore.delete()
        streamTask?.cancel()
        pollTask?.cancel()
        keyState = .missing
        clear()
    }

    private func clear() {
        me = nil
        grantedApps = []
        music = nil
        queue = []
        door = nil
        meeting = nil
        myBookings = []
        bentoOrders = []
        bentoDetail = [:]
        announcements = []
        errors = [:]
        connected = false
    }

    private func scheduleRetry() {
        pollTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            await self?.connect()
        }
    }

    /// Changes stream in; each one refreshes its app, batched briefly.
    private func listen() {
        let stream = ChangeStream(client: client)
        streamTask = Task { [weak self] in
            do {
                for try await event in stream.events() {
                    guard let self else { return }
                    switch event {
                    case .connected:
                        if !self.connected {
                            self.connected = true
                            await self.refreshAll(initial: false)
                        }
                    case .disconnected:
                        self.connected = false
                    case let .change(name):
                        if let app = self.app(ofChange: name) { self.enqueue(app) }
                    }
                }
            } catch {
                guard let self else { return }
                self.connected = false
                self.keyState = .invalid((error as? PortalError)?.localizedDescription ?? error.localizedDescription)
                self.scheduleRetry()
            }
        }
    }

    /// A slow safety net under the stream: the music position drifts, rooms
    /// free up with the clock, and a missed event heals within minutes.
    private func poll() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                await self?.refreshAll(initial: false)
            }
        }
    }

    func app(ofChange name: String) -> String? {
        if name.hasPrefix("player_") || name == "autoplay" { return "music" }
        if name == "card_swipe" { return "door" }
        if name.hasPrefix("room_") { return "meetings" }
        return appOfAction[name]
    }

    private func enqueue(_ app: String) {
        pending.insert(app)
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            let apps = self.pending
            self.pending = []
            for app in apps { await self.refresh(app: app) }
        }
    }

    // MARK: - Loading

    func refreshAll(initial: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            for app in ["music", "door", "meetings", "bento", "bulletin"] {
                group.addTask { await self.refresh(app: app, initial: initial) }
            }
        }
    }

    func refresh(app: String, initial: Bool = false) async {
        guard grantedApps.contains(app) else { return }
        switch app {
        case "music": await loadMusic()
        case "door": await load(.door) { self.door = try await self.client.run(GetDoorStatus.self, .init()) }
        case "meetings":
            await load(.meeting) {
                self.meeting = try await self.client.run(GetNextLabMeeting.self, .init()).meeting
                self.scheduleMeetingReminder()
            }
            await loadRooms()
        case "bento": await loadBento(initial: initial)
        case "bulletin": await loadAnnouncements(initial: initial)
        default: break
        }
    }

    private func load(_ section: MenuSection, _ work: () async throws -> Void) async {
        do {
            try await work()
            errors[section] = nil
        } catch let error as PortalError {
            if case .contract = error { outdated = true; updater?.checkInBackground() }
            errors[section] = error.localizedDescription
        } catch {
            errors[section] = error.localizedDescription
        }
    }

    private func loadMusic() async {
        let before = music?.current?.id
        await load(.music) {
            async let now = self.client.run(NowPlaying.self, .init())
            async let list = self.client.run(ListQueue.self, .init())
            self.music = try await now
            self.musicFetchedAt = Date()
            self.queue = try await list.items
        }
        if let current = music?.current, before != nil, current.id != before,
           UserDefaults.standard.bool(forKey: Pref.notifySong) {
            notifier.post(id: "song-\(current.id)", title: current.track.title, body: current.track.artist)
        }
    }

    private func loadRooms() async {
        await load(.rooms) {
            // Mine, from today through the next two days.
            let bookings = try await self.client.run(ListMeetings.self, .init(date: Self.today(), days: 3))
            let me = self.me
            self.myBookings = bookings.bookings.filter { b in
                b.cancelledAt == nil && (b.requestedBy == me?.id || b.attendees.contains { $0.email == me?.email })
            }
        }
    }

    private func loadBento(initial: Bool) async {
        await load(.bento) {
            let orders = try await self.client.run(ListBentoOrders.self, .init(limit: 10, status: .open)).orders
            self.bentoOrders = orders
            for order in orders {
                self.bentoDetail[order.id] = try await self.client.run(GetBentoOrder.self, .init(orderId: order.id))
            }
            self.bentoDetail = self.bentoDetail.filter { id, _ in orders.contains { $0.id == id } }
            let seen = Set(UserDefaults.standard.stringArray(forKey: Pref.seenBentoOrders) ?? [])
            if !initial || !seen.isEmpty, UserDefaults.standard.bool(forKey: Pref.notifyBento) {
                for order in orders where !seen.contains(order.id) {
                    self.notifier.post(id: "bento-\(order.id)", title: "便當開單了", body: order.restaurant)
                }
            }
            UserDefaults.standard.set(Array(seen.union(orders.map(\.id)).suffix(200)), forKey: Pref.seenBentoOrders)
        }
    }

    private func loadAnnouncements(initial: Bool) async {
        await load(.bulletin) {
            let list = try await self.client.run(ListAnnouncements.self, .init(limit: 20)).announcements
            self.announcements = list
            let seen = Set(UserDefaults.standard.stringArray(forKey: Pref.seenAnnouncements) ?? [])
            // The first run on a Mac only learns what exists.
            if !seen.isEmpty, UserDefaults.standard.bool(forKey: Pref.notifyAnnouncements) {
                for a in list where !seen.contains(a.id) {
                    self.notifier.post(id: "announcement-\(a.id)", title: a.title, body: String(a.content.prefix(200)))
                }
            }
            UserDefaults.standard.set(Array(seen.union(list.map(\.id)).suffix(200)), forKey: Pref.seenAnnouncements)
        }
    }

    // MARK: - Music

    /// Seconds into the song now, counting from the last fetch while playing.
    func position(at date: Date) -> Double {
        guard let music else { return 0 }
        let elapsed = music.paused || music.state != .playing ? 0 : date.timeIntervalSince(musicFetchedAt)
        let position = music.positionS + elapsed
        if let duration = music.current?.track.durationS { return min(position, duration) }
        return position
    }

    func togglePause() async {
        guard let music else { return }
        await perform(.music) {
            _ = try await self.client.run(SetPaused.self, .init(paused: !music.paused))
        }
    }

    func skip() async {
        guard let id = music?.current?.id else { return }
        await perform(.music) {
            _ = try await self.client.run(SkipSong.self, .init(itemId: id))
        }
    }

    func setVolume(_ volume: Int) async {
        let clamped = max(0, min(100, volume))
        await perform(.music) {
            _ = try await self.client.run(SetVolume.self, .init(volume: clamped))
        }
    }

    func nudgeVolume(_ direction: Int) async {
        guard let music else { return }
        let step = UserDefaults.standard.integer(forKey: Pref.volumeStep)
        await setVolume(Int(music.volume.rounded()) + direction * max(1, step))
    }

    // MARK: - Door

    func openDoor() async {
        await perform(.door) {
            let result = try await self.client.run(OpenDoor.self, .init())
            self.show(result.opened ? "門開了" : "門沒有開")
        }
    }

    // MARK: - Bento

    func order(_ orderId: String, item: String, options: [String], quantity: Int) async -> Bool {
        var ok = false
        await perform(.bento) {
            let result = try await self.client.run(
                AddBentoOrderItem.self,
                .init(items: [.init(menuItemId: item, optionValueIds: options, quantity: quantity)], orderId: orderId)
            )
            self.show("點好了，共 \(Int(result.total)) 元")
            ok = true
        }
        return ok
    }

    func myLines(in orderId: String) -> [GetBentoOrder.Output.Line] {
        bentoDetail[orderId]?.lines.filter { $0.userId == me?.id } ?? []
    }

    // MARK: - Meetings

    /// When the next lab meeting starts, from its date and HH:MM in Taipei.
    var meetingStart: Date? {
        guard let meeting, meeting.kind != .holiday else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.taipei
        let d = meeting.date.split(separator: "-").compactMap { Int($0) }
        let t = meeting.startsAt.split(separator: ":").compactMap { Int($0) }
        guard d.count == 3, t.count >= 2 else { return nil }
        return calendar.date(from: DateComponents(year: d[0], month: d[1], day: d[2], hour: t[0], minute: t[1]))
    }

    private func scheduleMeetingReminder() {
        guard UserDefaults.standard.bool(forKey: Pref.notifyMeeting), let start = meetingStart, let meeting else {
            notifier.cancel(id: "meeting")
            return
        }
        let lead = UserDefaults.standard.integer(forKey: Pref.meetingLeadMinutes)
        let fire = start.addingTimeInterval(-Double(lead) * 60)
        guard fire > Date() else { return }
        var body = meeting.location
        if let presenter = meeting.presenter?.name { body = "\(presenter) 報告，\(body)" }
        notifier.schedule(id: "meeting", at: fire, title: "週會 \(lead) 分鐘後開始", body: body)
    }

    // MARK: - Helpers

    /// Runs an action, then refreshes its app right away (the stream would
    /// too, a moment later).
    private func perform(_ section: MenuSection, _ work: () async throws -> Void) async {
        do {
            try await work()
            errors[section] = nil
            await refresh(app: section.app)
        } catch let error as PortalError {
            if case .contract = error { outdated = true; updater?.checkInBackground() }
            show(error.localizedDescription)
        } catch {
            show(error.localizedDescription)
        }
    }

    func show(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func openPortal(_ path: String = "") {
        NSWorkspace.shared.open(Self.portalURL.appending(path: path))
    }

    static func today() -> String {
        let f = DateFormatter()
        f.timeZone = taipei
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// HH:MM now in Taipei, to compare with room runs.
    static func nowHHMM() -> String {
        let f = DateFormatter()
        f.timeZone = taipei
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }
}
