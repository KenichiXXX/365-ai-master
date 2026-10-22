import XCTest
import UserNotifications
@testable import AIMaster

@MainActor
final class ReminderTests: XCTestCase {
    private func calendar(_ zone: String = "Asia/Tokyo") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func defaults() -> UserDefaults { UserDefaults(suiteName: UUID().uuidString)! }
    private func snapshot(day: String = "2026-10-19", state: String = "unavailable", review: Bool = true) throws -> Snapshot {
        let weekly = review ? #", "weekly":{"week_start":"2026-10-19","cards_lit_this_week":[],"quests_passed_this_week":[],"days_active":1,"report_text":"Observed practice","observed_change":{"text":"Observed practice","metric_id":"practice.new_observations","evidence_ids":["safe-evidence"]}}"# : ""
        return try EngineRunner.decode(Data("""
        {"schema":3,"book":{"lit":0,"total":1,"cards":[],"today":{"id":"web_search","title":"Search","why":"Why","prompt":"Try","level":1,"lit":false,"content_revision":"v1"},"practice_calendar":{"days":[{"date":"\(day)","state":"\(state)"}],"labels":{"observed":"Observed practice"}}}\(weekly)}
        """.utf8), status: 0).snapshot
    }
    private func context(_ snapshot: Snapshot?, daily: Bool = true, weekly: Bool = true,
                         pro: Bool = true, paused: Bool = false, hour: Int = 9, minute: Int = 0) -> ReminderContext {
        ReminderContext(snapshot: snapshot, daily: daily, weekly: weekly, reviewEntitled: pro,
                        paused: paused, hour: hour, minute: minute, locale: "en")
    }

    func testOldPermissionRequestIsNotExplicitReminderConsent() async {
        let defaults = defaults()
        defaults.set(true, forKey: "weeklyPermissionRequested")
        let store = SnapshotStore(defaults: defaults)
        await store.notificationTask?.value
        XCTAssertFalse(store.notificationsEnabled)
        XCTAssertFalse(store.dailyPracticeReminders)
    }

    func testCombinedOneShotDefaultSlotDedupeAndRestart() async throws {
        let center = ReminderCenterFake()
        let defaults = defaults()
        let clock = ReminderClock(date("2026-10-18T23:00:00Z"))
        var scheduler = WeeklyNotifications(center: center, defaults: defaults, clock: { clock.now }, calendar: calendar())
        let input = context(try snapshot())
        await scheduler.schedule(context: input)
        await scheduler.schedule(context: input)
        scheduler = WeeklyNotifications(center: center, defaults: defaults, clock: { clock.now }, calendar: calendar())
        await scheduler.schedule(context: input)
        XCTAssertEqual(center.added.count, 1)
        let request = try XCTUnwrap(center.pending.values.first)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.year, 2026)
        XCTAssertEqual(trigger.dateComponents.month, 10)
        XCTAssertEqual(trigger.dateComponents.day, 19)
        XCTAssertEqual(trigger.dateComponents.hour, 9)
        XCTAssertEqual(trigger.dateComponents.minute, 0)
        XCTAssertEqual(trigger.dateComponents.timeZone?.identifier, "Asia/Tokyo")
        XCTAssertEqual(request.content.userInfo["daily_id"] as? String, "web_search")
        XCTAssertEqual(request.content.userInfo["daily_date"] as? String, "2026-10-19")
        XCTAssertEqual(request.content.userInfo["review_id"] as? String, "2026-10-19")
        XCTAssertTrue(request.content.body.contains("Continue today's practice"))
        XCTAssertTrue(request.content.body.contains("Weekly review"))
        XCTAssertEqual(center.prompts, 0)
    }

    func testFreeDailyAndNoNewContentCompletedOrInvalidReviewAreSkipped() async throws {
        let center = ReminderCenterFake()
        let scheduler = WeeklyNotifications(center: center, defaults: defaults(),
            clock: { self.date("2026-10-18T23:00:00Z") }, calendar: calendar())
        await scheduler.schedule(context: context(try snapshot(), pro: false))
        XCTAssertEqual(center.pending.count, 1)
        XCTAssertNil(center.pending.values.first?.content.userInfo["review_id"])
        await scheduler.schedule(context: context(try snapshot(state: "observed"), pro: false))
        XCTAssertTrue(center.pending.isEmpty)
        for input in [context(nil), context(try snapshot(review: false), daily: false),
                      context(try snapshot(state: "self_reported"), weekly: false)] {
            await scheduler.schedule(context: input)
            XCTAssertTrue(center.pending.isEmpty)
        }
        XCTAssertEqual(center.added.count, 1)
    }

    func testQuietHoursSelectedSlotAndWakeSkipping() async throws {
        for (instant, hour, expected) in [("2026-10-18T23:00:00Z", 8, 0),
                                         ("2026-10-18T23:00:00Z", 21, 0),
                                         ("2026-10-19T01:00:00Z", 9, 0),
                                         ("2026-10-19T01:00:00Z", 14, 1)] {
            let center = ReminderCenterFake()
            let scheduler = WeeklyNotifications(center: center, defaults: defaults(),
                clock: { self.date(instant) }, calendar: calendar())
            await scheduler.schedule(context: context(try snapshot(), hour: hour, minute: 30))
            XCTAssertEqual(center.pending.count, expected)
            if let request = center.pending.values.first,
               let trigger = request.trigger as? UNCalendarNotificationTrigger {
                XCTAssertEqual(trigger.dateComponents.hour, 14)
                XCTAssertEqual(trigger.dateComponents.minute, 30)
            }
        }
        let center = ReminderCenterFake()
        let clock = ReminderClock(date("2026-10-18T23:00:00Z"))
        let scheduler = WeeklyNotifications(center: center, defaults: defaults(), clock: { clock.now }, calendar: calendar())
        await scheduler.schedule(context: context(try snapshot()))
        clock.now = date("2026-10-19T04:00:00Z")
        await scheduler.schedule(context: context(try snapshot()))
        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertEqual(center.added.count, 1)
    }

    func testOffPauseAndEntitlementLossCancelWithoutRetry() async throws {
        for mode in ["off", "pause", "expiry"] {
            let center = ReminderCenterFake()
            let scheduler = WeeklyNotifications(center: center, defaults: defaults(),
                clock: { self.date("2026-10-18T23:00:00Z") }, calendar: calendar())
            let snap = try snapshot()
            await scheduler.schedule(context: context(snap, daily: false))
            XCTAssertEqual(center.pending.count, 1)
            await scheduler.schedule(context: context(snap, daily: false, weekly: mode != "off",
                pro: mode != "expiry", paused: mode == "pause"))
            XCTAssertTrue(center.pending.isEmpty)
            await scheduler.schedule(context: context(snap, daily: false))
            XCTAssertTrue(center.pending.isEmpty)
        }
    }

    func testDeliveredDateNeverRepeatsAfterTravelRollbackOrContentChange() async throws {
        let center = ReminderCenterFake()
        let prefs = defaults()
        let clock = ReminderClock(date("2026-10-18T23:00:00Z"))
        let scheduler = WeeklyNotifications(center: center, defaults: prefs, clock: { clock.now }, calendar: calendar())
        await scheduler.schedule(context: context(try snapshot()))
        center.pending.removeAll() // macOS consumed the one-shot request.
        let travelling = WeeklyNotifications(center: center, defaults: prefs, clock: { clock.now }, calendar: calendar("America/Los_Angeles"))
        clock.now = date("2026-10-19T15:00:00Z")
        await travelling.schedule(context: context(try snapshot(), weekly: false))
        XCTAssertEqual(center.added.count, 1)
    }


    func testUnchangedDailyContentIsNotResentOnAnotherDay() async throws {
        let center = ReminderCenterFake()
        let clock = ReminderClock(date("2026-10-18T23:00:00Z"))
        let scheduler = WeeklyNotifications(center: center, defaults: defaults(), clock: { clock.now }, calendar: calendar())
        await scheduler.schedule(context: context(try snapshot(), weekly: false))
        center.pending.removeAll()
        clock.now = date("2026-10-19T23:00:00Z")
        await scheduler.schedule(context: context(try snapshot(day: "2026-10-20"), weekly: false))
        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertEqual(center.added.count, 1)
    }

    func testWakeDuringAuthorizationLookupDoesNotSchedulePastSlot() async throws {
        let center = ReminderCenterFake()
        let clock = ReminderClock(date("2026-10-18T23:00:00Z"))
        center.onStatus = { clock.now = self.date("2026-10-19T02:00:00Z") }
        let scheduler = WeeklyNotifications(center: center, defaults: defaults(), clock: { clock.now }, calendar: calendar())
        await scheduler.schedule(context: context(try snapshot()))
        XCTAssertTrue(center.pending.isEmpty)
    }

    func testEnablingWhilePausedAsksOnceAndKeepsPendingWorkCancelled() async {
        let center = ReminderCenterFake()
        center.authorization = .notDetermined
        let prefs = defaults()
        prefs.set(true, forKey: "remindersPaused")
        let scheduler = WeeklyNotifications(center: center, defaults: prefs)
        let store = SnapshotStore(defaults: prefs, weeklyNotifications: scheduler)
        await store.notificationTask?.value
        XCTAssertEqual(center.prompts, 0)
        store.dailyPracticeReminders = true
        await store.notificationTask?.value
        XCTAssertEqual(center.prompts, 1)
        XCTAssertTrue(center.pending.isEmpty)
        store.remindersPaused = false
        await store.notificationTask?.value
        XCTAssertEqual(center.prompts, 1)
    }

    func testDenialNeverRepromptsAndEnablingIsTheOnlyPromptTrigger() async throws {
        let center = ReminderCenterFake()
        center.authorization = .notDetermined
        center.grant = false
        let defaults = defaults()
        let scheduler = WeeklyNotifications(center: center, defaults: defaults)
        let store = SnapshotStore(defaults: defaults, weeklyNotifications: scheduler)
        await store.notificationTask?.value
        XCTAssertEqual(center.prompts, 0)
        store.dailyPracticeReminders = true
        await store.notificationTask?.value
        XCTAssertEqual(center.prompts, 1)
        store.dailyPracticeReminders = false
        store.dailyPracticeReminders = true
        await store.notificationTask?.value
        XCTAssertEqual(center.prompts, 1)
        let restarted = SnapshotStore(defaults: defaults, weeklyNotifications: scheduler)
        await restarted.notificationTask?.value
        XCTAssertEqual(center.prompts, 1)
        XCTAssertTrue(center.pending.isEmpty)
        center.authorization = .denied
        let allowed = await scheduler.requestPermission()
        XCTAssertFalse(allowed)
        XCTAssertEqual(center.prompts, 1)
    }

    func testExactSafeInternalRoutingAndLegacyCalendarDecoding() async throws {
        let store = SnapshotStore(defaults: defaults())
        let snap = try snapshot()
        store.load = { _, _ in EngineResult(snapshot: snap, json: "{}") }
        await store.refresh()?.value
        XCTAssertTrue(store.openReminder(["daily_id": "web_search", "daily_date": "2026-10-19"]))
        XCTAssertEqual(store.reminderCard?.id, "web_search")
        XCTAssertFalse(store.openReminder(["daily_id": "https://example.com", "daily_date": "2026-10-19"]))
        XCTAssertFalse(store.openReminder(["daily_id": "web_search", "daily_date": "2026-10-18"]))
        XCTAssertFalse(store.openReminder(["review_id": "2026-10-19"])) // Free cannot open Pro review.
        let legacy = try EngineRunner.decode(Data(#"{"schema":2}"#.utf8), status: 0).snapshot
        XCTAssertNil(legacy.book?.practiceCalendar)
        XCTAssertEqual(snap.book?.practiceCalendar?.days.first?.accessibilityLabel(labels: ["unavailable": "Data unavailable"]),
                       "Oct 19, Data unavailable")
    }
}

@MainActor
private final class ReminderClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@MainActor
private final class ReminderCenterFake: ReminderNotificationCenter {
    var authorization: ReminderAuthorization = .authorized
    var grant = true
    var prompts = 0
    var added: [UNNotificationRequest] = []
    var pending: [String: UNNotificationRequest] = [:]
    var onStatus: (() -> Void)?
    func status() async -> ReminderAuthorization { onStatus?(); return authorization }
    func requestPermission() async -> Bool {
        prompts += 1
        authorization = grant ? .authorized : .denied
        return grant
    }
    func add(_ request: UNNotificationRequest) async throws {
        added.append(request)
        pending[request.identifier] = request
    }
    func pendingRequests() async -> [UNNotificationRequest] { Array(pending.values) }
    func cancel() { pending.removeAll() }
}
