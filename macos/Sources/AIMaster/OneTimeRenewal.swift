import Foundation
import UserNotifications

enum OneTimeRenewal {
    static func expiryDate(_ license: License.Payload, calendar: Calendar = .current) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: license.exp)
    }

    static func daysRemaining(_ license: License.Payload?, now: Date, calendar: Calendar = .current) -> Int? {
        guard let license, license.isOneTimeAnnual, let expiry = expiryDate(license, calendar: calendar),
              let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: expiry).day,
              (0...7).contains(days) else { return nil }
        return days
    }

    static func message(days: Int, zh: Bool) -> String {
        zh ? "Pro 将于 \(days) 天后到期 · 续费" : "Pro expires in \(days) days · Renew"
    }
}

@MainActor
protocol OneTimeReminderCenter {
    func status() async -> ReminderAuthorization
    func add(_ request: UNNotificationRequest) async throws
    func remove(_ identifiers: [String])
}

@MainActor
private final class SystemOneTimeReminderCenter: OneTimeReminderCenter {
    private let center = UNUserNotificationCenter.current()
    func status() async -> ReminderAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        default: return .denied
        }
    }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
    func remove(_ identifiers: [String]) { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
}

@MainActor
final class OneTimeRenewalNotifications {
    private let center: OneTimeReminderCenter
    private let defaults: UserDefaults
    private let clock: () -> Date
    private let calendar: Calendar
    private var generation = 0
    private let marker = "oneTimeRenewalNotification"

    init(center: OneTimeReminderCenter? = nil, defaults: UserDefaults = .standard,
         clock: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.center = center ?? SystemOneTimeReminderCenter()
        self.defaults = defaults
        self.clock = clock
        self.calendar = calendar
    }

    func schedule(license: License.Payload?, locale: String) async {
        generation += 1
        let revision = generation
        let id = license.flatMap { $0.isOneTimeAnnual ? "one-time-renewal-" + $0.lic + "-" + $0.exp : nil }
        if let old = defaults.string(forKey: marker), old != id {
            center.remove([old])
            defaults.removeObject(forKey: marker)
        }
        guard let license, let id, defaults.string(forKey: marker) != id,
              let expiry = OneTimeRenewal.expiryDate(license, calendar: calendar),
              let reminder = calendar.date(byAdding: .day, value: -7, to: expiry),
              let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: reminder),
              License.day(clock()) <= license.exp,
              await center.status() == .authorized, generation == revision else { return }
        let fire = max(morning, clock().addingTimeInterval(1))
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: fire), to: expiry).day ?? 0
        let content = UNMutableNotificationContent()
        content.title = OneTimeRenewal.message(days: days, zh: locale == "zh")
        content.body = locale == "zh" ? "微信支付 / 支付宝 · 一次付一年，不自动续费" : "WeChat Pay / Alipay · one year, no auto-renewal"
        content.userInfo = ["one_time_lic": license.lic, "one_time_exp": license.exp]
        content.sound = .default
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
        components.timeZone = calendar.timeZone
        let request = UNNotificationRequest(identifier: id, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        do {
            try await center.add(request)
            guard generation == revision else { center.remove([id]); return }
            defaults.set(id, forKey: marker)
        } catch { /* A later local refresh can retry a failed schedule. */ }
    }
}
