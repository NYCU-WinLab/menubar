import PortalKit
import SwiftUI

// MARK: - Music

struct MusicSection: View {
    @Environment(AppModel.self) private var model
    @State private var volume: Double?
    @State private var showQueue = false

    var body: some View {
        if let music = model.music {
            VStack(alignment: .leading, spacing: 12) {
                if let current = music.current {
                    HStack(spacing: 12) {
                        Artwork(url: current.track.thumbnail)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(current.track.title).font(.headline).lineLimit(1)
                            Text(current.track.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            if let by = current.addedBy {
                                Text("\(by) 點的").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    if let duration = current.track.durationS, duration > 0 {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let position = model.position(at: context.date)
                            VStack(spacing: 4) {
                                ProgressCapsule(value: position / duration)
                                HStack {
                                    Text(clock(position))
                                    Spacer()
                                    Text("-" + clock(duration - position))
                                }
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Notice(text: "沒有在播")
                }
                HStack(spacing: 10) {
                    Button {
                        Task { await model.togglePause() }
                    } label: {
                        Image(systemName: music.paused ? "play.fill" : "pause.fill")
                            .frame(width: 22, height: 22)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .circleButton(prominent: true)
                    .help(music.paused ? "繼續" : "暫停")
                    Button {
                        Task { await model.skip() }
                    } label: {
                        Image(systemName: "forward.fill")
                            .frame(width: 22, height: 22)
                    }
                    .circleButton()
                    .disabled(music.current == nil)
                    .help("下一首")
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.fill")
                        Slider(
                            value: Binding(get: { volume ?? music.volume }, set: { volume = $0 }),
                            in: 0 ... 100
                        ) { editing in
                            if !editing, let v = volume {
                                Task {
                                    await model.setVolume(Int(v.rounded()))
                                    volume = nil
                                }
                            }
                        }
                        .controlSize(.small)
                        Image(systemName: "speaker.wave.3.fill")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("音量 \(Int((volume ?? music.volume).rounded()))")
                }
                if !music.online {
                    Notice(text: "實驗室的播放器離線", symbol: "exclamationmark.triangle")
                }
                HStack {
                    if !model.queue.isEmpty {
                        Button {
                            withAnimation(.smooth) { showQueue.toggle() }
                        } label: {
                            Label("接下來 \(model.queue.count) 首", systemImage: "chevron.right")
                                .labelStyle(TrailingIcon(rotated: showQueue))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("點歌") { model.openPortal("music") }
                        .glassButton()
                        .controlSize(.small)
                }
                .font(.caption)
                if showQueue {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.queue.prefix(8), id: \.id) { item in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.track.title).font(.callout).lineLimit(1)
                                Text(item.track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Text, then a chevron that turns when the group is open.
struct TrailingIcon: LabelStyle {
    var rotated: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
                .imageScale(.small)
                .rotationEffect(.degrees(rotated ? 90 : 0))
        }
    }
}

struct Artwork: View {
    let url: String?

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:)).map(Self.larger)) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Image(systemName: "music.note").foregroundStyle(.secondary)
        }
        .frame(width: 52, height: 52)
        .background(.fill.tertiary)
        .clipShape(.rect(cornerRadius: Metrics.artworkRadius, style: .continuous))
    }

    /// YouTube Music thumbnails come at 60 px; ask for 120 for Retina.
    static func larger(_ url: URL) -> URL {
        let text = url.absoluteString.replacingOccurrences(of: "=w60-h60", with: "=w120-h120")
        return URL(string: text) ?? url
    }
}

// MARK: - Door

struct DoorSection: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Pref.confirmDoor) private var confirm = true
    @State private var armed = false

    var body: some View {
        HStack(spacing: 10) {
            if let door = model.door {
                Circle()
                    .fill(door.online ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(door.online ? "門禁在線" : (door.configured ? "門禁離線" : "門禁未設定"))
                    .font(.callout)
            }
            Spacer()
            Button {
                if confirm, !armed {
                    withAnimation(.smooth) { armed = true }
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation(.smooth) { armed = false }
                    }
                    return
                }
                armed = false
                Task { await model.openDoor() }
            } label: {
                Label(armed ? "再按一次" : "開門", systemImage: "lock.open.fill")
            }
            .glassButton(prominent: true)
            .tint(armed ? .orange : nil)
            .disabled(model.door?.online == false)
        }
    }
}

// MARK: - Meeting

struct MeetingSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let meeting = model.meeting {
            if meeting.kind == .holiday {
                Notice(text: "\(meeting.date) 放假\(meeting.holiday.map { "，\($0)" } ?? "")", symbol: "sun.max")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(model.meetingStart?.formatted(Self.when) ?? "\(meeting.date) \(meeting.startsAt)")
                            .font(.headline)
                        Spacer()
                        if let start = model.meetingStart, start > Date() {
                            Text(start, format: .relative(presentation: .named))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if let presenter = meeting.presenter?.name {
                            Text("\(presenter) 報告").font(.callout)
                        }
                        if let title = meeting.paper?.title ?? meeting.title {
                            Text(title).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Label(meeting.location, systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        if let join = meeting.joinUrl.flatMap(URL.init(string:)) {
                            Link(destination: join) { Label("加入 Teams", systemImage: "video.fill") }
                                .glassButton(prominent: true)
                        }
                        if let slides = meeting.slidesUrl.flatMap(URL.init(string:)) {
                            Link("投影片", destination: slides).glassButton()
                        }
                        Spacer()
                        Button("週會頁") { model.openPortal("meetings") }.glassButton()
                    }
                    .controlSize(.small)
                }
            }
        } else {
            Notice(text: "還沒排下一次週會")
        }
    }

    static let when: Date.FormatStyle = {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: Locale(identifier: "zh-Hant-TW"), timeZone: AppModel.taipei)
        style = style.month(.defaultDigits).day().weekday(.abbreviated).hour().minute()
        return style
    }()
}

// MARK: - Rooms

struct RoomsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let now = AppModel.nowHHMM()
            let runs = (model.roomsToday?.runs ?? []).filter { $0.end > now }.prefix(4)
            if runs.isEmpty {
                Notice(text: "今天沒有可借的時段了")
            }
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(color(run.tier)).frame(width: 6, height: 6)
                    Text("\(run.start) 到 \(run.end)")
                        .font(.callout.monospacedDigit())
                    Text(describe(run))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if !model.myBookings.isEmpty {
                Divider()
                ForEach(model.myBookings.prefix(3), id: \.id) { b in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(b.title).font(.callout).lineLimit(1)
                            Text("\(b.date.suffix(5)) \(b.startTime)\(b.room.map { "，\($0)" } ?? "")")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let join = b.meeting?.joinUrl.flatMap(URL.init(string:)) {
                            Link("加入", destination: join).glassButton().controlSize(.small)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("借會議室") { model.openPortal("meetings") }
                    .glassButton()
                    .controlSize(.small)
            }
        }
    }

    private func describe(_ run: ListRoomAvailability.Output.Day.Run) -> String {
        switch run.tier {
        case .free: run.freeRooms.joined(separator: "、")
        case .lab: "實驗室 " + run.labRooms.joined(separator: "、")
        case .paid: "付費 " + run.paidRooms.joined(separator: "、")
        case .full, .unknown: "都滿了"
        }
    }

    private func color(_ tier: ListRoomAvailability.Output.Day.Run.Tier) -> Color {
        switch tier {
        case .free: .green
        case .lab: .blue
        case .paid: .orange
        case .full, .unknown: .secondary
        }
    }
}

// MARK: - Bento

struct BentoSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.bentoOrders.isEmpty {
            Notice(text: "目前沒有開單")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.bentoOrders, id: \.id) { order in
                    let mine = model.myLines(in: order.id)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(order.restaurant).font(.headline)
                            Text("\(order.date)，\(Int(order.people)) 人點了 \(Int(order.dishes)) 份")
                                .font(.caption).foregroundStyle(.secondary)
                            if !mine.isEmpty {
                                Text("我點了：\(mine.map(\.name).joined(separator: "、"))")
                                    .font(.caption).lineLimit(2)
                            }
                        }
                        Spacer()
                        Button(mine.isEmpty ? "點餐" : "加點") {
                            withAnimation(.smooth) { model.openBentoOrder = order.id }
                        }
                        .glassButton(prominent: mine.isEmpty)
                        .disabled(model.bentoDetail[order.id] == nil)
                    }
                }
            }
        }
    }
}

/// Order from one open bento order: pick a dish, its options, how many.
struct BentoOrderView: View {
    let orderId: String
    @Environment(AppModel.self) private var model
    @State private var dish: String?
    @State private var choices: [String: Set<String>] = [:]
    @State private var quantity = 1
    @State private var sending = false

    var body: some View {
        let detail = model.bentoDetail[orderId]
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    withAnimation(.smooth) { model.openBentoOrder = nil }
                } label: {
                    Image(systemName: "chevron.left").frame(width: 16, height: 16)
                }
                .circleButton()
                .help("返回")
                Spacer()
                Text(detail?.restaurant.name ?? "便當").font(.headline)
                Spacer()
                Button {
                    model.openPortal("bento")
                } label: {
                    Image(systemName: "safari").frame(width: 16, height: 16)
                }
                .circleButton()
                .help("在 portal 開啟")
            }
            .padding(Metrics.modulePadding)
            Divider()
            if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        menu(detail)
                        if dish != nil { options(detail) }
                    }
                    .padding(Metrics.modulePadding)
                }
                .frame(maxHeight: 460)
                Divider()
                footer(detail).padding(Metrics.modulePadding)
            } else {
                ProgressView().padding(24).frame(maxWidth: .infinity)
            }
        }
        .background(.fill.quaternary, in: .rect(cornerRadius: Metrics.moduleRadius, style: .continuous))
    }

    private func menu(_ detail: GetBentoOrder.Output) -> some View {
        let categories = Dictionary(grouping: detail.menu, by: \.category)
        let order = detail.menu.map(\.category).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(order, id: \.self) { category in
                if !category.isEmpty {
                    Text(category).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(categories[category] ?? [], id: \.id) { item in
                    Button {
                        dish = item.id
                    } label: {
                        HStack {
                            Image(systemName: dish == item.id ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(dish == item.id ? Color.accentColor : .secondary)
                            Text(item.name)
                            Spacer()
                            Text("\(Int(item.price))").monospacedDigit().foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func options(_ detail: GetBentoOrder.Output) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(detail.optionGroups, id: \.id) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name + (group.required ? "（必選）" : ""))
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(group.values, id: \.id) { value in
                        let selected = choices[group.id, default: []].contains(value.id)
                        Button {
                            toggle(value.id, in: group)
                        } label: {
                            HStack {
                                Image(systemName: group.multiple
                                    ? (selected ? "checkmark.square.fill" : "square")
                                    : (selected ? "largecircle.fill.circle" : "circle"))
                                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                                Text(value.label)
                                Spacer()
                                if value.priceDelta != 0 {
                                    Text("+\(Int(value.priceDelta))").monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 6)
    }

    private func footer(_ detail: GetBentoOrder.Output) -> some View {
        let missing = detail.optionGroups.filter { $0.required && choices[$0.id, default: []].isEmpty }
        return HStack {
            Stepper("\(quantity) 份", value: $quantity, in: 1 ... 10).fixedSize()
            Spacer()
            if !missing.isEmpty, dish != nil {
                Text("選\(missing.map(\.name).joined(separator: "、"))").font(.caption).foregroundStyle(.secondary)
            }
            Button(sending ? "送出中" : "點餐") {
                guard let dish else { return }
                sending = true
                Task {
                    let ok = await model.order(orderId, item: dish, options: choices.values.flatMap { $0 }, quantity: quantity)
                    sending = false
                    if ok { model.openBentoOrder = nil }
                }
            }
            .glassButton(prominent: true)
            .keyboardShortcut(.defaultAction)
            .disabled(dish == nil || !missing.isEmpty || sending)
        }
    }

    private func toggle(_ value: String, in group: GetBentoOrder.Output.OptionGroup) {
        var set = choices[group.id, default: []]
        if group.multiple {
            if set.contains(value) { set.remove(value) } else { set.insert(value) }
        } else {
            set = set.contains(value) && !group.required ? [] : [value]
        }
        choices[group.id] = set
    }
}

// MARK: - Bulletin

struct BulletinSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.announcements.isEmpty {
            Notice(text: "沒有公告")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.announcements.prefix(3), id: \.id) { a in
                    Button {
                        model.openPortal("bulletin")
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.title).font(.callout).lineLimit(1)
                            HStack(spacing: 4) {
                                if let author = a.author { Text(author) }
                                Text(a.createdAt, format: .relative(presentation: .named))
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
