import XCTest
import SwiftUI
@testable import AIMaster

@MainActor
final class MePageTests: XCTestCase {
    func testProgressDecodesAndOldSnapshotsStayCompatible() throws {
        let old = try EngineRunner.decode(Data(#"{"schema":3}"#.utf8), status: 0).snapshot
        XCTAssertNil(old.progressMe)
        let data = Data(#"{"schema":3,"progress_me":{"vs_yesterday":2,"personal_best":74,"week_delta":5}}"#.utf8)
        let me = try XCTUnwrap(EngineRunner.decode(data, status: 0).snapshot.progressMe)
        XCTAssertEqual(me.vsYesterday, 2)
        XCTAssertEqual(me.personalBest, 74)
        XCTAssertEqual(me.weekDelta, 5)
        XCTAssertEqual(me.caption(locale: "zh"), "个人最佳 74 · 本周 +5")
        XCTAssertEqual(me.caption(locale: "en"), "Personal best 74 · This week +5")
        let unknown = try EngineRunner.decode(Data(#"{"schema":3,"progress_me":{"vs_yesterday":null,"personal_best":null,"week_delta":null}}"#.utf8), status: 0).snapshot
        XCTAssertNil(unknown.progressMe?.caption(locale: "zh"))
    }

    func testTrendCopyAndRankStates() {
        XCTAssertEqual(MePresentation.yesterday(2, locale: "zh"), "▲ 比昨天 +2")
        XCTAssertEqual(MePresentation.yesterday(-1, locale: "zh"), "▼ 比昨天 −1")
        XCTAssertEqual(MePresentation.yesterday(0, locale: "zh"), "= 与昨天持平")
        XCTAssertNil(MePresentation.yesterday(nil, locale: "en"))
        XCTAssertEqual(MePresentation.yesterday(-1, locale: "en"), "▼ −1 vs yesterday")
        XCTAssertEqual(MePresentation.rankChange(3, locale: "zh"), "本周排名 ▲3")
        XCTAssertEqual(MePresentation.rankChange(-2, locale: "en"), "Weekly rank ▼2")
        XCTAssertEqual(MePresentation.rankChange(0, locale: "zh"), "本周排名 =")
        XCTAssertNil(MePresentation.rankChange(nil, locale: "zh"))
        XCTAssertEqual(CheckupPresentation.rankCaption(.init(total: 20, rank: 8, percentile: 63, small_sample: false), locale: "zh"), "超过全球 63% 的 AI 用户")
        XCTAssertEqual(CheckupPresentation.rankCaption(.init(total: 3, rank: 2, percentile: nil, small_sample: true), locale: "zh"), "早期排名 · 3 人中第 2 名")
    }

    func testBarsHighlightOnlyKnownExtremesAndHandleTies() {
        let dims = [Dimension(key: "routing", label: "Routing", score: 40),
                    Dimension(key: "context", label: "Context", score: 80),
                    Dimension(key: "timing", label: "Timing", score: 60),
                    Dimension(key: "leverage", label: "Leverage", score: nil)]
        XCTAssertEqual(MePresentation.barAccent(dims[0], in: dims), .lowest)
        XCTAssertEqual(MePresentation.barAccent(dims[1], in: dims), .highest)
        XCTAssertEqual(MePresentation.barAccent(dims[2], in: dims), .neutral)
        XCTAssertEqual(MePresentation.barAccent(dims[3], in: dims), .neutral)
        let tied = dims.map { Dimension(key: $0.key, label: $0.label, score: 60) }
        XCTAssertTrue(tied.allSatisfy { MePresentation.barAccent($0, in: tied) == .neutral })
    }

    func testRankHistoryUsesExactCalendarDaySurvivesRestartAndNeverDatesCacheAsFresh() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "shareAnonymousScore")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let first = calendar.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 23))!
        let today = calendar.date(byAdding: .day, value: 7, to: first)!
        var rank = 10
        var status = 200
        var calls = 0
        let transport: ScoreReporter.Transport = { _ in
            calls += 1
            return (Data("{\"score_version\":\"1\",\"total\":30,\"rank\":\(rank),\"percentile\":63,\"small_sample\":false}".utf8), status)
        }
        let reporter = ScoreReporter(defaults: defaults, transport: transport)
        let dims = ScoreReporter.Dims(routing: 70, timing: 70, context: 70, leverage: 70)
        _ = await reporter.report(score: 70, dims: dims, appVersion: "1", now: first, calendar: calendar)
        XCTAssertNil(reporter.rankChange7d(now: first, calendar: calendar))
        rank = 7
        _ = await reporter.report(score: 70, dims: dims, appVersion: "1", now: today, calendar: calendar)
        XCTAssertEqual(reporter.rankChange7d(now: today, calendar: calendar), 3)
        XCTAssertEqual(calls, 2)
        let restarted = ScoreReporter(defaults: defaults, transport: transport)
        XCTAssertEqual(restarted.rankChange7d(now: today, calendar: calendar), 3)
        XCTAssertNil(restarted.rankChange7d(scoreVersion: "2", now: today, calendar: calendar))
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        XCTAssertNotNil(restarted.cached(now: tomorrow))
        XCTAssertNil(restarted.rankChange7d(now: tomorrow, calendar: calendar))
        status = 500
        _ = await restarted.report(score: 70, dims: dims, appVersion: "1", now: tomorrow, calendar: calendar)
        XCTAssertNil(restarted.rankChange7d(now: tomorrow, calendar: calendar))
        defaults.set(false, forKey: "shareAnonymousScore")
        XCTAssertNil(restarted.rankChange7d(now: today, calendar: calendar))
    }

    func testGlobalRankStoreIntegrationAndRenderingWithRealResponses() async throws {
        let now = Date()
        let before = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -7, to: now))
        let result = try EngineRunner.decode(Data(#"{"schema":3,"overall":{"score_version":"1","score":69},"dimensions":[{"key":"routing","label":"Routing","score":35},{"key":"timing","label":"Timing","score":70},{"key":"context","label":"Context","score":95},{"key":"leverage","label":"Leverage","score":75}]}"#.utf8), status: 0)
        for total in [3, 30] {
            let defaults = UserDefaults(suiteName: UUID().uuidString)!
            defaults.set(true, forKey: "shareAnonymousScore")
            var rank = total == 3 ? 3 : 10
            let reporter = ScoreReporter(defaults: defaults, transport: { _ in
                let percentile = total < 20 ? "null" : "63"
                return (Data("{\"score_version\":\"1\",\"total\":\(total),\"rank\":\(rank),\"percentile\":\(percentile),\"small_sample\":\(total < 20)}".utf8), 200)
            })
            _ = await reporter.report(score: 69, dims: .init(routing: 35, timing: 70, context: 95, leverage: 75), appVersion: "1", now: before)
            rank = total == 3 ? 2 : 7
            let store = SnapshotStore(defaults: defaults, load: { _, _ in result }, scoreReporter: reporter)
            await store.refresh()?.value
            XCTAssertEqual(store.ranking?.rank, rank)
            XCTAssertEqual(store.rankChange7d, total == 3 ? 1 : 3)
            for locale in ["zh", "en"] {
                for scheme in [ColorScheme.light, .dark] {
                    let renderer = ImageRenderer(content: GlobalRankCard(store: store, locale: locale)
                        .frame(width: 408).bauhausTheme().environment(\.colorScheme, scheme))
                    let image = try XCTUnwrap(renderer.nsImage)
                    XCTAssertEqual(image.size.width, 408)
                    XCTAssertLessThanOrEqual(image.size.height, 160)
                    if let output = ProcessInfo.processInfo.environment["RENDER_OUT"] {
                        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
                        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                            .write(to: URL(fileURLWithPath: output + "-global-\(total)-\(locale)-\(scheme).png"))
                    }
                }
            }
            store.shareAnonymousScore = false
            XCTAssertNil(store.ranking)
            XCTAssertNil(store.rankChange7d)
        }
    }

    func testMePageRendersBothLanguagesAppearancesAndUnknowns() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures"))
        let base = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        for locale in ["zh", "en"] {
            for delta in [2, -1, 0] {
                for known in [true, false] {
                    var object = base
                    object["locale"] = locale
                    object["progress_me"] = known ? ["vs_yesterday": delta, "personal_best": 74, "week_delta": 5] : [:]
                    if known {
                        object["overall"] = ["score": 69, "score_version": "1"]
                        object["dimensions"] = zip(["routing", "timing", "context", "leverage"], [35, 70, 95, 75]).map {
                            ["key": $0, "label": $0, "score": $1] as [String: Any]
                        }
                    } else { object["overall"] = ["score": NSNull()]; object["dimensions"] = [] }
                    let result = try EngineRunner.decode(JSONSerialization.data(withJSONObject: object), status: 0)
                    let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
                    for scheme in [ColorScheme.light, .dark] {
                        let renderer = ImageRenderer(content: CheckupTab(snapshot: result.snapshot, store: store)
                            .padding(16).frame(width: 440).environment(\.colorScheme, scheme))
                        let image = try XCTUnwrap(renderer.nsImage)
                        XCTAssertEqual(image.size.width, 440)
                        XCTAssertLessThanOrEqual(image.size.height, 650)
                    }
                }
            }
        }
    }
}
