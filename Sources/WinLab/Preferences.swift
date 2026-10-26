import Foundation

/// UserDefaults keys, one place, so views and the model agree.
enum Pref {
    static let menuBarText = "menuBarText"
    static let notify = "notify"
    static let launchAtLoginOffered = "launchAtLoginOffered"
    static let seenAnnouncements = "seenAnnouncements"
    static let seenBentoOrders = "seenBentoOrders"

    /// Fixed choices that used to be settings.
    static let titleWidth = 160
    static let lyricWidth = 240
    static let volumeStep = 5
    static let meetingLeadMinutes = 10

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [menuBarText: MenuBarText.lyrics.rawValue, notify: true])
    }
}

/// The parts of the menu, in order; each can be hidden in Settings.
enum MenuSection: String, CaseIterable, Identifiable, Codable {
    case music, door, meeting, rooms, bento, bulletin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music: "音樂"
        case .door: "門禁"
        case .meeting: "週會"
        case .rooms: "會議室"
        case .bento: "便當"
        case .bulletin: "公告"
        }
    }

    var symbol: String {
        switch self {
        case .music: "music.note"
        case .door: "door.left.hand.open"
        case .meeting: "person.3"
        case .rooms: "calendar"
        case .bento: "takeoutbag.and.cup.and.straw"
        case .bulletin: "megaphone"
        }
    }

    /// The portal API app the key needs for this section.
    var app: String {
        switch self {
        case .music: "music"
        case .door: "door"
        case .meeting, .rooms: "meetings"
        case .bento: "bento"
        case .bulletin: "bulletin"
        }
    }
}

/// What the menu bar shows beside the icon while a song plays.
enum MenuBarText: String, CaseIterable, Identifiable {
    case lyrics, title, none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lyrics: "歌詞"
        case .title: "歌名"
        case .none: "不顯示"
        }
    }

    static var current: MenuBarText {
        MenuBarText(rawValue: UserDefaults.standard.string(forKey: Pref.menuBarText) ?? "") ?? .lyrics
    }
}
