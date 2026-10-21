import Foundation
import UserNotifications

struct ReminderContext {
    let snapshot: Snapshot?
    let daily: Bool
    let weekly: Bool
    let reviewEntitled: Bool
    let paused: Bool
    let hour: Int
    let minute: Int
    let locale: String
}

enum ReminderAuthorization { case notDetermined, authorized, denied }

@MainActor
protocol ReminderNotificationCenter {
    func status() async -> ReminderAuthorization
    func requestPermission() async -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func pendingRequests() async -> [UNNotificationRequest]
    func cancel()
}

@MainActor
private final class SystemReminderCenter: ReminderNotificationCenter {
    private let center = UNUserNotificationCenter.current()
    func status() async -> ReminderAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }
    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
    func pendingRequests() async -> [UNNotificationRequest] { await center.pendingNotificationRequests() }
    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [WeeklyNotifications.identifier, "weekly-review"])
    }
}

@MainActor
protocol WeeklyNotificationScheduling {
    func requestPermission() async -> Bool
    func schedule(context: ReminderContext) async
    func cancel()
}

@MainActor
final class WeeklyNotifications: WeeklyNotificationScheduling {
    static let identifier = "practice-review"
    private let center: ReminderNotificationCenter
    private let defaults: UserDefaults
    private let clock: () -> Date
    private let calendar: () -> Calendar
    private var generation = 0

    init(center: ReminderNotificationCenter? = nil, defaults: UserDefaults = .standard,
         clock: @escaping () -> Date = Date.init, calendar: Calendar? = nil) {
        self.center = center ?? SystemReminderCenter()
        self.defaults = defaults
        self.clock = clock
        self.calendar = { calendar ?? Calendar.current }
    }

    func requestPermission() async -> Bool {
        switch await center.status() {
        case .authorized: return true
        case .denied: return false
        case .notDetermined: return await center.requestPermission()
        }
    }

    func schedule(context: ReminderContext) async {
        let revision = generation
        let calendar = calendar()
        let now = clock()
        let day = Self.localDate(now, calendar: calendar)
        guard !context.paused, context.daily || (context.weekly && context.reviewEntitled),
              (9..<21).contains(context.hour), (0..<60).contains(context.minute),
              let fire = calendar.date(bySettingHour: context.hour, minute: context.minute, second: 0, of: now),
              fire > now else { cancel(); return }
        let snapshot = context.snapshot
        let currentDay = snapshot?.book?.practiceCalendar?.days.last
        let completed = currentDay?.date == day && ["observed", "self_reported"].contains(currentDay?.state ?? "")
        let card = context.daily && !completed && currentDay?.date == day ? snapshot?.book?.today : nil
        let review = context.weekly && context.reviewEntitled && calendar.component(.weekday, from: now) == 2
            && snapshot?.weekly?.weekStart == day && snapshot?.weekly?.hasReminderContent == true ? snapshot?.weekly : nil
        let ledger = defaults.dictionary(forKey: "reminderDates") as? [String: String] ?? [:]
        let contentKey = (card?.id ?? "") + "|" + (card?.contentRevision ?? "") + "|"
        let alreadySuggested = ledger.contains { $0.key != day && $0.value.hasPrefix(contentKey) }
        let dailyID = card.flatMap { Self.safeID($0.id) && !alreadySuggested ? $0.id : nil }
        let reviewID = review?.weekStart
        guard dailyID != nil || reviewID != nil else { cancel(); return }
        guard await center.status() == .authorized, revision == generation else { cancel(); return }
        let pending = await center.pendingRequests()
        guard revision == generation else { return }
        let existing = pending.first { $0.identifier == Self.identifier }
        var updatedLedger = ledger
        guard fire > clock(), Self.localDate(clock(), calendar: calendar) == day else { cancel(); return }
        let signature = [dailyID ?? "", card?.contentRevision ?? "", reviewID ?? "",
                         String(fire.timeIntervalSince1970)].joined(separator: "|")
        // A consumed or cancelled date is never retried, even after travel or clock rollback.
        if let previous = ledger[day] {
            let pendingDay = (existing?.content.userInfo["daily_date"] ?? existing?.content.userInfo["review_id"]) as? String
            guard pendingDay == day, previous != signature else { return }
        }
        var route: [String: String] = [:]
        if let dailyID { route["daily_id"] = dailyID; route["daily_date"] = day }
        if let reviewID { route["review_id"] = reviewID }
        let request = Self.request(route: route, fire: fire, calendar: calendar, locale: context.locale)
        do {
            try await center.add(request)
            guard revision == generation else { center.cancel(); return }
            updatedLedger[day] = signature
            defaults.set(updatedLedger, forKey: "reminderDates")
        } catch {
            updatedLedger[day] = signature
            defaults.set(updatedLedger, forKey: "reminderDates")
        }
    }

    func cancel() {
        generation += 1
        center.cancel()
    }

    static func localDate(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    static func safeID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 80 && id.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_:-").contains($0)
        }
    }

    static func request(route: [String: String], fire: Date, calendar: Calendar, locale: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        let daily = route["daily_id"] != nil
        let weekly = route["review_id"] != nil
        content.title = daily ? (locale == "zh" ? "每日练习提醒" : "Daily practice reminder")
            : (locale == "zh" ? "周复盘提醒" : "Weekly review reminder")
        content.body = [daily ? (locale == "zh" ? "继续今天的一步" : "Continue today's practice") : nil,
                        weekly ? (locale == "zh" ? "本周复盘" : "Weekly review") : nil].compactMap { $0 }.joined(separator: " · ")
        content.userInfo = route
        content.sound = .default
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }
}

extension WeeklyReview {
    var hasReminderContent: Bool {
        guard reportText?.isEmpty == false else { return false }
        return observedChange?.evidenceIds?.isEmpty == false || selfReportIds?.isEmpty == false
            || reuseEvidenceIds?.isEmpty == false
    }
}
