import XCTest
import CryptoKit
import UserNotifications
import SwiftUI
@testable import AIMaster

@MainActor
final class ProFeaturesTests: XCTestCase {
    private let signingKey = Curve25519.Signing.PrivateKey()
    private func key() throws -> String {
        let data = Data(#"{"v":1,"lic":"abcdefghijklmnop","plan":"pro","iat":"2026-10-21","exp":"2099-01-01"}"#.utf8)
        func encode(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        return "AIM1.\(encode(data)).\(encode(try signingKey.signature(for: data)))"
    }
    private func store(notifications: NotificationSpy? = nil) -> SnapshotStore {
        SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
            licensePublicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString(),
            weeklyNotifications: notifications)
    }
    func testFreeAndProGateEachFeature() throws {
        let store = store()
        let today = SkillCard(id: "today", title: "Today", why: "Why", prompt: "Prompt", level: 1, lit: false, how: nil)
        let other = SkillCard(id: "other", title: "Other", why: "Why", prompt: "Secret prompt", level: 1, lit: false, how: nil)
        let lit = SkillCard(id: "lit", title: "Lit", why: "Why", prompt: "Prompt", level: 1, lit: true, how: "log")
        let rows = (1...25).map { Ranking(name: "Row \($0)", url: "https://example.com", tagline: "Tag", installed: false) }
        XCTAssertFalse(store.features.growthCurve)
        XCTAssertFalse(store.features.weeklyReview)
        XCTAssertTrue(store.features.canLearn(today, todayID: today.id))
        XCTAssertTrue(store.features.canLearn(lit, todayID: today.id))
        XCTAssertFalse(store.features.canLearn(other, todayID: today.id))
        XCTAssertEqual(store.features.discoverRankings(rows).count, 10)
        store.openWeeklyReview()
        XCTAssertFalse(store.showWeeklyReview)
        XCTAssertTrue(store.activateLicense(try key()))
        XCTAssertTrue(store.features.growthCurve)
        XCTAssertTrue(store.features.weeklyReview)
        XCTAssertTrue(store.features.canLearn(other, todayID: today.id))
        XCTAssertEqual(store.features.discoverRankings(rows).count, 20)
        store.openWeeklyReview()
        XCTAssertTrue(store.showWeeklyReview)
    }
    func testTrialUsesAllExistingFeatureGatesAndExpiryKeepsFreePractice() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var state: Data?
        var transports = 0
        var downloads = 0
        let reporter = ScoreReporter(defaults: defaults, transport: { _ in
            transports += 1
            throw URLError(.notConnectedToInternet)
        })
        let result = try EngineRunner.decode(Data(#"{"schema":3,"overall":{"score":80,"score_version":"1"},"dimensions":[{"key":"routing","label":"Routing","score":80},{"key":"timing","label":"Timing","score":80},{"key":"context","label":"Context","score":80},{"key":"leverage","label":"Leverage","score":80}]}"#.utf8), status: 0)
        let notifications = NotificationSpy()
        let store = SnapshotStore(defaults: defaults, load: { _, _ in result }, scoreReporter: reporter,
            weeklyNotifications: notifications,
            proTrial: ProTrial(clock: { now }, read: { state }, write: { state = $0 }))
        store.downloadContent = { downloads += 1; return false }
        let today = SkillCard(id: "today", title: "Today", why: "Why", prompt: "Prompt", level: 1, lit: false, how: nil)
        let other = SkillCard(id: "other", title: "Other", why: "Why", prompt: "Prompt", level: 1, lit: false, how: nil)
        let lit = SkillCard(id: "lit", title: "Lit", why: "Why", prompt: "Prompt", level: 1, lit: true, how: "log")
        let rows = (1...25).map { Ranking(name: "Row \($0)", url: "https://example.com", tagline: "Tag", installed: false) }
        for phase in 0...2 {
            if phase == 1 { store.startProTrial() }
            if phase == 2 { now += 14 * 86400; store.resumeEntitlement() }
            await store.refresh()?.value
            await store.refreshContent().value
            await store.notificationTask?.value
            let pro = phase == 1
            XCTAssertEqual(store.features.growthCurve, pro)
            XCTAssertEqual(store.features.weeklyReview, pro)
            XCTAssertEqual(store.features.canLearn(other, todayID: today.id), pro)
            XCTAssertTrue(store.features.canLearn(today, todayID: today.id))
            XCTAssertTrue(store.features.canLearn(lit, todayID: today.id))
            XCTAssertEqual(store.features.discoverRankings(rows).count, pro ? 20 : 10)
            XCTAssertNil(store.features.dimensionCaption(store.ranking, key: "routing", locale: "en"))
            XCTAssertEqual(store.snapshotJSON, result.json)
        }
        XCTAssertEqual(transports, 0)
        XCTAssertEqual(downloads, 0)
        XCTAssertEqual(notifications.requests, 0)
        XCTAssertNil(defaults.string(forKey: "anonDeviceToken"))
    }

    func testTrialDimensionComparisonStillRequiresSeparateRankingConsent() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var data: Data?
        var calls = 0
        let reporter = ScoreReporter(defaults: defaults, transport: { _ in
            calls += 1
            return (Data(#"{"score_version":"1","total":20,"rank":5,"percentile":80,"small_sample":false,"dims":{"routing":{"rank":5,"percentile":80},"timing":{"rank":5,"percentile":80},"context":{"rank":5,"percentile":80},"leverage":{"rank":5,"percentile":80}}}"#.utf8), 200)
        })
        let result = try EngineRunner.decode(Data(#"{"schema":3,"overall":{"score":80,"score_version":"1"},"dimensions":[{"key":"routing","label":"Routing","score":80},{"key":"timing","label":"Timing","score":80},{"key":"context","label":"Context","score":80},{"key":"leverage","label":"Leverage","score":80}]}"#.utf8), status: 0)
        let store = SnapshotStore(defaults: defaults, load: { _, _ in result }, scoreReporter: reporter,
            proTrial: ProTrial(read: { data }, write: { data = $0 }))
        store.startProTrial()
        await store.refresh()?.value
        XCTAssertNil(store.features.dimensionCaption(store.ranking, key: "routing", locale: "en"))
        XCTAssertEqual(calls, 0)
        await store.allowScoreSharing()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.features.dimensionCaption(store.ranking, key: "routing", locale: "en"), "Beat 80%")
        store.shareAnonymousScore = false
        XCTAssertNil(store.features.dimensionCaption(store.ranking, key: "routing", locale: "en"))
    }

    func testExpiredTrialRemovesWeeklyReminderAndPreservesDailyPreference() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "dailyPracticeReminders")
        defaults.set(true, forKey: "notificationsEnabled")
        let notifications = NotificationSpy()
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var data: Data?
        let store = SnapshotStore(defaults: defaults, weeklyNotifications: notifications,
            proTrial: ProTrial(clock: { now }, read: { data }, write: { data = $0 }))
        store.startProTrial()
        await store.notificationTask?.value
        XCTAssertTrue(notifications.context?.reviewEntitled == true)
        now += 14 * 86400
        store.openWeeklyReview()
        await store.notificationTask?.value
        XCTAssertTrue(notifications.context?.daily == true)
        XCTAssertFalse(notifications.context?.reviewEntitled == true)
        XCTAssertTrue(store.dailyPracticeReminders)
        XCTAssertEqual(notifications.requests, 0)
    }

    func testDecodesGrowthWeeklyAndOldSnapshots() throws {
        let data = Data(#"{"schema":2,"growth":{"days":[{"date":"2026-10-21","score":88}],"week_delta":3},"weekly":{"week_start":"2026-10-19","score_delta":3,"cards_lit_this_week":["a"],"quests_passed_this_week":["first_edit"],"days_active":2}}"#.utf8)
        let snapshot = try EngineRunner.decode(data, status: 0).snapshot
        XCTAssertEqual(snapshot.growth?.days.first?.score, 88)
        XCTAssertEqual(snapshot.growth?.weekDelta, 3)
        XCTAssertEqual(snapshot.weekly?.weekStart, "2026-10-19")
        XCTAssertEqual(snapshot.weekly?.cardsLitThisWeek, ["a"])
        XCTAssertEqual(snapshot.weekly?.questsPassedThisWeek, ["first_edit"])
        XCTAssertEqual(snapshot.weekly?.daysActive, 2)
        let old = try EngineRunner.decode(Data(#"{"schema":2}"#.utf8), status: 0).snapshot
        XCTAssertNil(old.growth)
        XCTAssertNil(old.weekly)
    }
    func testUnversionedDeltaNeverBecomesAnImprovementClaimInEitherLanguage() throws {
        let snapshot = try EngineRunner.decode(Data(#"{"schema":3,"weekly":{"week_start":"2026-10-19","score_delta":20,"cards_lit_this_week":[],"quests_passed_this_week":[],"days_active":3}}"#.utf8), status: 0).snapshot
        for locale in ["zh", "en"] {
            let text = try XCTUnwrap(snapshot.weekly).summary(locale: locale)
            XCTAssertEqual(text, locale == "zh" ? "可比数据积累中" : "Collecting comparable data")
            XCTAssertFalse(text.contains("20"))
            XCTAssertFalse(text.contains("%"))
            let caption = UsageSummary(tokens7d: 12, costUsd7d: 500, codexQuotaPct: 80).details(locale: locale)
            XCTAssertTrue(caption.contains(locale == "zh" ? "非订阅账单" : "not a subscription bill"))
            XCTAssertFalse(caption.contains("500"))
            XCTAssertFalse(caption.contains("saved"))
            XCTAssertFalse(caption.contains("节省"))
        }
    }

    func testUnknownScoresDoNotChangeEntitlementsOrAcquireAPercentile() throws {
        let snapshot = try EngineRunner.decode(Data(#"{"schema":3,"overall":{"score":null,"tier":null},"dimensions":[{"key":"routing","label":"Routing","score":null}],"growth":{"days":[],"week_delta":null}}"#.utf8), status: 0).snapshot
        XCTAssertFalse(snapshot.hasEvaluableScores)
        XCTAssertTrue(snapshot.growth?.days.isEmpty == true)
        for pro in [false, true] {
            let features = ProFeatures(isPro: pro)
            XCTAssertEqual(features.growthCurve, pro)
            XCTAssertNil(features.dimensionCaption(nil, key: "routing", locale: "en"))
            let renderer = ImageRenderer(content: DimensionRings(dimensions: snapshot.dimensions!,
                features: features).frame(width: 408))
            XCTAssertNotNil(renderer.nsImage)
        }
    }

    private func contains<T>(_ type: T.Type, in value: Any) -> Bool {
        if value is T { return true }
        return Mirror(reflecting: value).children.contains { contains(type, in: $0.value) }
    }

    func testViewsUseProGatesAndRenderInBothLanguages() throws {
        let store = store()
        let card = SkillCard(id: "other", title: "Other", why: "Why", prompt: "Secret prompt", level: 1, lit: false, how: nil)
        for pro in [false, true] {
            if pro { XCTAssertTrue(store.activateLicense(try key())) }
            for locale in ["zh", "en"] {
                let data = Data("""
                {"schema":2,"locale":"\(locale)","growth":{"days":[{"date":"2026-10-20","score":80},{"date":"2026-10-21","score":88}],"week_delta":3},"weekly":{"week_start":"2026-10-19","score_delta":3,"cards_lit_this_week":[],"quests_passed_this_week":[],"days_active":2}}
                """.utf8)
                let snapshot = try EngineRunner.decode(data, status: 0).snapshot
                let dimension = Dimension(key: "routing", label: "Routing", score: 80)
                let dimensionDetails = DimensionDetail(dimension: dimension, growth: snapshot.growth,
                    features: store.features, locale: locale, store: store, back: {})
                XCTAssertFalse(contains(GrowthCurve.self, in: CheckupTab(snapshot: snapshot, store: store).body))
                XCTAssertEqual(contains(GrowthCurve.self, in: dimensionDetails.body), pro)
                let details = SkillCardDetails(card: card, todayID: "today", store: store, locale: locale)
                XCTAssertEqual(contains(PracticeControls.self, in: details.body), pro)
                let today = SkillCardDetails(card: card, todayID: card.id, store: store, locale: locale)
                XCTAssertTrue(contains(PracticeControls.self, in: today.body))
                let views: [(String, AnyView)] = [
                    ("checkup", AnyView(CheckupTab(snapshot: snapshot, store: store))),
                    ("dimension", AnyView(dimensionDetails)),
                    ("skill", AnyView(details)),
                    ("weekly", AnyView(WeeklyReviewSheet(snapshot: snapshot)))
                ]
                for (name, view) in views where pro || name != "weekly" {
                    let content = view.padding(16).frame(width: 440)
                        .background(Color(nsColor: .windowBackgroundColor))
                    let bitmap: NSBitmapImageRep
                    if name == "weekly" {
                        let hosting = NSHostingView(rootView: content)
                        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
                        hosting.layoutSubtreeIfNeeded()
                        bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                    } else {
                        let renderer = ImageRenderer(content: content)
                        renderer.scale = 2
                        let image = try XCTUnwrap(renderer.nsImage)
                        XCTAssertEqual(image.size.width, 440)
                        XCTAssertGreaterThan(image.size.height, 30)
                        bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
                    }
                    if let out = ProcessInfo.processInfo.environment["RENDER_OUT"] {
                        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                            .write(to: URL(fileURLWithPath: "\(out)-\(name)-\(locale)-\(pro ? "pro" : "free").png"))
                    }
                }
            }
        }
    }

    func testLegacyPermissionDoesNotEnableRemindersAndExpiryCancels() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(try key(), forKey: "licenseKey")
        defaults.set(true, forKey: "weeklyPermissionRequested")
        let notifications = NotificationSpy()
        let store = SnapshotStore(defaults: defaults,
            licensePublicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString(),
            weeklyNotifications: notifications)
        await store.notificationTask?.value
        XCTAssertEqual(notifications.requests, 0)
        XCTAssertEqual(notifications.scheduled, 0)
        store.openWeeklyReview()
        XCTAssertTrue(store.showWeeklyReview)
        let cancellations = notifications.cancellations
        defaults.set("invalid", forKey: "licenseKey")
        store.openWeeklyReview()
        XCTAssertFalse(store.showWeeklyReview)
        XCTAssertFalse(store.features.growthCurve)
        XCTAssertGreaterThan(notifications.cancellations, cancellations)
    }

    func testPermissionOnlyAfterExplicitPreferenceAndDaytimeSlot() async throws {
        let notifications = NotificationSpy()
        let store = store(notifications: notifications)
        await store.notificationTask?.value
        XCTAssertEqual(notifications.requests, 0)
        XCTAssertFalse(store.activateLicense("invalid"))
        XCTAssertTrue(store.activateLicense(try key()))
        await store.notificationTask?.value
        XCTAssertEqual(notifications.requests, 0)
        store.notificationsEnabled = true
        await store.notificationTask?.value
        XCTAssertEqual(notifications.requests, 1)
        XCTAssertEqual(notifications.scheduled, 1)
        XCTAssertTrue(store.activateLicense(try key()))
        await store.notificationTask?.value
        XCTAssertEqual(notifications.requests, 1)
        XCTAssertEqual(notifications.context?.hour, 9)
        XCTAssertEqual(notifications.context?.minute, 0)
        XCTAssertTrue(notifications.context?.weekly == true)
        XCTAssertTrue(notifications.context?.reviewEntitled == true)
    }
}

@MainActor
private final class NotificationSpy: WeeklyNotificationScheduling {
    var requests = 0
    var scheduled = 0
    var cancellations = 0
    func requestPermission() async -> Bool { requests += 1; return true }
    var context: ReminderContext?
    func schedule(context: ReminderContext) async { scheduled += 1; self.context = context }
    func cancel() { cancellations += 1 }
}
