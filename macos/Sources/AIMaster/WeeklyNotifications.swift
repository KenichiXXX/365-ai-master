import Foundation
import UserNotifications

@MainActor
protocol WeeklyNotificationScheduling {
    func requestPermission() async -> Bool
    func schedule(review: WeeklyReview?, locale: String) async
    func cancel()
}

@MainActor
final class WeeklyNotifications: WeeklyNotificationScheduling {
    static let identifier = "weekly-review"
    private let center = UNUserNotificationCenter.current()

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func schedule(review: WeeklyReview?, locale: String) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        try? await center.add(Self.request(review: review, locale: locale))
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }

    static func request(review: WeeklyReview?, locale: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = locale == "zh" ? "本周复盘" : "Weekly review"
        content.body = review?.summary(locale: locale) ?? (locale == "zh" ? "查看你的分数、技能与新手村进展" : "Review your scores, skills and village progress")
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 9, minute: 0, weekday: 2), repeats: true)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }
}
