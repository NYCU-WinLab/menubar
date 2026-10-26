import PortalKit
import SwiftUI

// MARK: - Music

struct MusicSection: View {
    @Environment(AppModel.self) private var model
    @State private var volume: Double?

    var body: some View {
        if let music = model.music {
            VStack(alignment: .leading, spacing: 8) {
                if let current = music.current {
                    HStack(spacing: 10) {
                        Artwork(url: current.track.thumbnail)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(current.track.title).font(.body.weight(.medium)).lineLimit(1)
                            Text(current.track.artist).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                            if let by = current.addedBy {
                                Text("\(by) 點的").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    if let duration = current.track.durationS, duration > 0 {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let position = model.position(at: context.date)
                            VStack(spacing: 2) {
                                ProgressView(value: position, total: duration)
                                    .progressViewStyle(.linear)
                                HStack {
                                    Text(clock(position))
                                    Spacer()
                                    Text(clock(duration))
                                }
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("沒有在播").font(.callout).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Button {
                        Task { await model.togglePause() }
                    } label: {
                        Image(systemName: music.paused ? "play.fill" : "pause.fill").frame(width: 18)
                    }
                    .help(music.paused ? "繼續" : "暫停")
                    Button {
                        Task { await model.skip() }
                    } label: {
                        Image(systemName: "forward.fill")
                    }
                    .disabled(music.current == nil)
                    .help("下一首")
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary).font(.caption)
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
                    Text("\(Int((volume ?? music.volume).rounded()))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                }
                .buttonStyle(.borderless)
                if !music.online {
                    Label("實驗室的播放器離線", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                if !model.queue.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("接下來").font(.caption).foregroundStyle(.secondary)
                        ForEach(model.queue.prefix(3), id: \.id) { item in
                            Text("\(item.track.title)，\(item.track.artist)")
                                .font(.caption).lineLimit(1)
                        }
                        if model.queue.count > 3 {
                            Text("還有 \(model.queue.count - 3) 首").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                Button("點歌") { model.openPortal("music") }
                    .buttonStyle(.link).font(.caption)
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

struct Artwork: View {
    let url: String?

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Image(systemName: "music.note").foregroundStyle(.secondary)
        }
        .frame(width: 44, height: 44)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Door

struct DoorSection: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Pref.confirmDoor) private var confirm = true
    @State private var armed = false

    var body: some View {
        HStack {
            if let door = model.door {
                Circle().fill(door.online ? Color.green : Color.red).frame(width: 7, height: 7)
                Text(door.online ? "門禁在線" : (door.configured ? "門禁離線" : "門禁未設定"))
                    .font(.callout)
            }
            Spacer()
            Button(armed ? "再按一次開門" : "開門") {
                if confirm, !armed {
                    armed = true
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        armed = false
                    }
                    return
                }
                armed = false
                Task { await model.openDoor() }
            }
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
            VStack(alignment: .leading, spacing: 4) {
                if meeting.kind == .holiday {
                    Text("\(meeting.date) 放假\(meeting.holiday.map { "：\($0)" } ?? "")").font(.callout)
                } else {
                    HStack {
                        Text("\(meeting.date) \(meeting.startsAt)").font(.body.weight(.medium))
                        Spacer()
                        if let start = model.meetingStart, start > Date() {
                            Text(start, style: .relative).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(subtitle(meeting)).font(.callout).lineLimit(2)
                    Text(meeting.location).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        if let join = meeting.joinUrl.flatMap(URL.init(string:)) {
                            Link("加入 Teams", destination: join)
                        }
                        if let slides = meeting.slidesUrl.flatMap(URL.init(string:)) {
                            Link("投影片", destination: slides)
                        }
                        Button("週會頁") { model.openPortal("meetings") }.buttonStyle(.link)
                    }
                    .font(.caption)
                }
            }
        } else {
            Text("還沒排下一次週會").font(.callout).foregroundStyle(.secondary)
        }
    }

    private func subtitle(_ m: GetNextLabMeeting.Output.Meeting) -> String {
        var parts: [String] = []
        if let p = m.presenter?.name { parts.append("\(p) 報告") }
        if let title = m.paper?.title ?? m.title { parts.append(title) }
        if parts.isEmpty { return m.label ?? "週會" }
        return parts.joined(separator: "：")
    }
}

// MARK: - Rooms

struct RoomsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let now = AppModel.nowHHMM()
            let runs = (model.roomsToday?.runs ?? []).filter { $0.end > now }.prefix(4)
            if runs.isEmpty {
                Text("今天沒有可借的時段了").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                HStack(alignment: .firstTextBaseline) {
                    Text("\(run.start) 到 \(run.end)").font(.caption.monospacedDigit()).frame(width: 96, alignment: .leading)
                    Text(describe(run)).font(.caption).foregroundStyle(color(run.tier)).lineLimit(1)
                }
            }
            if !model.myBookings.isEmpty {
                Text("我的會議").font(.caption).foregroundStyle(.secondary).padding(.top, 2)
                ForEach(model.myBookings.prefix(3), id: \.id) { b in
                    HStack {
                        Text("\(b.date.suffix(5)) \(b.startTime)").font(.caption.monospacedDigit())
                        Text(b.title).font(.caption).lineLimit(1)
                        Spacer()
                        if let join = b.meeting?.joinUrl.flatMap(URL.init(string:)) {
                            Link("加入", destination: join).font(.caption)
                        } else if let room = b.room {
                            Text(room).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Button("借會議室") { model.openPortal("meetings") }
                .buttonStyle(.link).font(.caption)
        }
    }

    private func describe(_ run: ListRoomAvailability.Output.Day.Run) -> String {
        switch run.tier {
        case .free: "空：\(run.freeRooms.joined(separator: "、"))"
        case .lab: "實驗室：\(run.labRooms.joined(separator: "、"))"
        case .paid: "付費：\(run.paidRooms.joined(separator: "、"))"
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
            Text("目前沒有開單").font(.callout).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.bentoOrders, id: \.id) { order in
                    let mine = model.myLines(in: order.id)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(order.restaurant).font(.body.weight(.medium))
                            Text("\(order.date)，\(Int(order.people)) 人點了 \(Int(order.dishes)) 份")
                                .font(.caption).foregroundStyle(.secondary)
                            if !mine.isEmpty {
                                Text("我點了：\(mine.map(\.name).joined(separator: "、"))")
                                    .font(.caption).lineLimit(2)
                            }
                        }
                        Spacer()
                        Button(mine.isEmpty ? "點餐" : "加點") { model.openBentoOrder = order.id }
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
                    model.openBentoOrder = nil
                } label: {
                    Label("返回", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text(detail?.restaurant.name ?? "便當").font(.headline)
                Spacer()
                Button("網頁") { model.openPortal("bento") }.buttonStyle(.borderless)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()
            if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        menu(detail)
                        if dish != nil { options(detail) }
                    }
                    .padding(14)
                }
                .frame(maxHeight: 460)
                Divider()
                footer(detail).padding(14)
            } else {
                ProgressView().padding(24).frame(maxWidth: .infinity)
            }
        }
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
            Text("沒有公告").font(.callout).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.announcements.prefix(3), id: \.id) { a in
                    Button {
                        model.openPortal("bulletin")
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.title).font(.callout).lineLimit(1)
                            Text("\(a.author ?? "")  \(a.createdAt.formatted(date: .abbreviated, time: .omitted))")
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
