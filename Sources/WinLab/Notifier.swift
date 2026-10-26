import Foundation
import UserNotifications

/// macOS notifications: announcements, meeting reminders, new bento orders.
@MainActor
final class Notifier {
    private var center: UNUserNotificationCenter? {
        // Notifications need a bundle; `swift run` has none.
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    func requestPermission() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(id: String, title: String, body: String) {
        add(id: id, title: title, body: body, trigger: nil)
    }

    func schedule(id: String, at date: Date, title: String, body: String) {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        add(id: id, title: title, body: body, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
    }

    func cancel(id: String) {
        center?.removePendingNotificationRequests(withIdentifiers: [id])
    }

    private func add(id: String, title: String, body: String, trigger: UNNotificationTrigger?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center?.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
