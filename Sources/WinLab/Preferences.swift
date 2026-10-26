import Foundation

/// UserDefaults keys, one place, so views and the model agree.
enum Pref {
    static let showTitleInMenuBar = "showTitleInMenuBar"
    static let menuBarTitleWidth = "menuBarTitleWidth"
    static let sections = "sections"
    static let notifyAnnouncements = "notifyAnnouncements"
    static let notifyMeeting = "notifyMeeting"
    static let meetingLeadMinutes = "meetingLeadMinutes"
    static let notifyBento = "notifyBento"
    static let notifySong = "notifySong"
    static let confirmDoor = "confirmDoor"
    static let volumeStep = "volumeStep"
    static let seenAnnouncements = "seenAnnouncements"
    static let seenBentoOrders = "seenBentoOrders"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showTitleInMenuBar: true,
            menuBarTitleWidth: 160,
            notifyAnnouncements: true,
            notifyMeeting: true,
            meetingLeadMinutes: 10,
            notifyBento: true,
            notifySong: false,
            confirmDoor: true,
            volumeStep: 5,
        ])
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

    /// Sections shown, from Settings, as a comma-separated string (so views
    /// can watch it with @AppStorage); all by default.
    static var enabled: Set<MenuSection> { parse(UserDefaults.standard.string(forKey: Pref.sections)) }

    static func parse(_ raw: String?) -> Set<MenuSection> {
        guard let raw else { return Set(allCases) }
        return Set(raw.split(separator: ",").compactMap { MenuSection(rawValue: String($0)) })
    }

    static func store(_ sections: Set<MenuSection>) -> String {
        allCases.filter(sections.contains).map(\.rawValue).joined(separator: ",")
    }
}
