import Foundation
import UserNotifications

/// "Bike to events" reminders. Scheduled on the phone from the server's picked
/// events, 30 minutes before each starts. (These are local notifications: real
/// remote push would need an APNs key on the server.)
enum EventNotifier {
    static let leadTime: TimeInterval = 30 * 60
    private static let prefix = "event-"

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Replaces the event reminders with ones for `events`.
    static func schedule(_ events: [CampusEvent]) async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }

        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        for event in events {
            let fireDate = event.startDate.addingTimeInterval(-leadTime)
            guard fireDate > Date() else { continue }
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
                repeats: false)
            try? await center.add(UNNotificationRequest(identifier: prefix + event.id, content: content(for: event), trigger: trigger))
        }
    }

    /// For the demo: the first event's reminder, 5 seconds from now.
    static func sendTest(_ event: CampusEvent) async {
        guard await requestPermission() else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "event-test-\(UUID().uuidString)", content: content(for: event), trigger: trigger))
    }

    private static func content(for event: CampusEvent) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Bike to \(event.name)"
        content.body = event.invite
        content.sound = .default
        content.userInfo = ["eventId": event.id]
        return content
    }
}
