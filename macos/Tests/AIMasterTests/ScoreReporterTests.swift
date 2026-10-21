import XCTest
import SwiftUI
@testable import AIMaster

final class ScoreReporterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_540_800)
    private var dims: ScoreReporter.Dims { .init(routing: 60, timing: 70, context: 80, leverage: 90) }

    @MainActor func testConsentPlaceholderExactPayloadAndDailyGate() async throws {
        let defaults = UserDefaults(suiteName: "score-tests-" + UUID().uuidString)!
        var calls = 0
        var token: String?
        let reporter = ScoreReporter(defaults: defaults, endpoint: URL(string: "https://local.test/v1/score")!, transport: { request in
            calls += 1
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.allHTTPHeaderFields, ["Content-Type": "application/json"])
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertEqual(request.timeoutInterval, 15)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(Set(body.keys), ["device_token", "score", "dims", "app_version"])
            XCTAssertEqual(Set((body["dims"] as! [String: Int]).keys), ["routing", "timing", "context", "leverage"])
            XCTAssertEqual(body["score"] as? Int, 75)
            XCTAssertEqual(body["app_version"] as? String, "1.0")
            let id = try XCTUnwrap(body["device_token"] as? String)
            XCTAssertNotNil(UUID(uuidString: id))
            if let token { XCTAssertEqual(id, token) }
            token = id
            return (Data(#"{"score_version":"1","total":1,"rank":1,"percentile":null,"small_sample":true}"#.utf8), 200)
        })
        _ = await reporter.report(score: 75, dims: dims, appVersion: "1.0", now: now)
        XCTAssertEqual(calls, 0)
        XCTAssertNil(defaults.string(forKey: "anonDeviceToken"))
        defaults.set(true, forKey: "shareAnonymousScore")
        let placeholder = ScoreReporter(defaults: defaults,
                                        endpoint: URL(string: "https://365aimaster-ranking.REPLACE.workers.dev/v1/score")!,
                                        transport: { _ in
            XCTFail("Placeholder must not send"); return (Data(), 500)
        })
        _ = await placeholder.report(score: 75, dims: dims, appVersion: "1.0", now: now)
        XCTAssertNil(defaults.string(forKey: "anonDeviceToken"))
        let first = await reporter.report(score: 75, dims: dims, appVersion: "1.0", now: now)
        XCTAssertEqual(first?.total, 1)
        _ = await reporter.report(score: 75, dims: dims, appVersion: "1.0", now: now.addingTimeInterval(60))
        XCTAssertEqual(calls, 1)
        _ = await reporter.report(score: 75, dims: dims, appVersion: "1.0", now: now.addingTimeInterval(86400))
        XCTAssertEqual(calls, 2)
        defaults.set(false, forKey: "shareAnonymousScore")
        XCTAssertNil(reporter.cached(now: now.addingTimeInterval(86400)))
        _ = await reporter.report(score: 75, dims: dims, appVersion: "1.0", now: now.addingTimeInterval(172800))
        XCTAssertEqual(calls, 2)
    }

    @MainActor func testFailureAndCacheExpiry() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "shareAnonymousScore")
        var status = 200
        let reporter = ScoreReporter(defaults: defaults, endpoint: URL(string: "https://local.test/v1/score")!, transport: { _ in
            (Data(#"{"score_version":"1","total":25,"rank":13,"percentile":50,"small_sample":false}"#.utf8), status)
        })
        _ = await reporter.report(score: 75, dims: dims, appVersion: "1.0", now: now)
        XCTAssertEqual(reporter.cached(now: now.addingTimeInterval(6 * 86400))?.percentile, 50)
        XCTAssertNil(reporter.cached(now: now.addingTimeInterval(8 * 86400)))
        status = 503
        let result = await reporter.report(score: 75, dims: dims, appVersion: "1.0", now: now.addingTimeInterval(86400))
        XCTAssertNil(result)
        XCTAssertNil(reporter.cached(now: now.addingTimeInterval(86400)))
    }

    @MainActor func testFailedAttemptsAreDailyAndBadResponsesStayHidden() async throws {
        for response in [Data("bad json".utf8),
                         Data(#"{"score_version":"1","total":1,"rank":1,"percentile":99,"small_sample":false}"#.utf8)] {
            let defaults = UserDefaults(suiteName: UUID().uuidString)!
            defaults.set(true, forKey: "shareAnonymousScore")
            var calls = 0
            let reporter = ScoreReporter(defaults: defaults, endpoint: URL(string: "https://local.test/v1/score")!, transport: { _ in
                calls += 1
                return (response, 200)
            })
            let first = await reporter.report(score: 75, dims: dims, appVersion: "1.0", now: now)
            XCTAssertNil(first)
            _ = await reporter.report(score: 75, dims: dims, appVersion: "1.0", now: now.addingTimeInterval(60))
            XCTAssertEqual(calls, 1)
            XCTAssertNil(reporter.cached(now: now))
        }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "shareAnonymousScore")
        let reporter = ScoreReporter(defaults: defaults, endpoint: URL(string: "https://local.test/v1/score")!, transport: { _ in
            throw NSError(domain: "offline", code: 1)
        })
        let result = await reporter.report(score: 75, dims: dims, appVersion: "1.0", now: now)
        XCTAssertNil(result)
        XCTAssertNil(reporter.cached(now: now))
    }

    @MainActor func testTurningOffDiscardsAnInflightResultAndStoreDefaultsOff() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        XCTAssertFalse(SnapshotStore(defaults: defaults).shareAnonymousScore)
        defaults.set(true, forKey: "shareAnonymousScore")
        let reporter = ScoreReporter(defaults: defaults, endpoint: URL(string: "https://local.test/v1/score")!, transport: { _ in
            defaults.set(false, forKey: "shareAnonymousScore")
            return (Data(#"{"score_version":"1","total":1,"rank":1,"percentile":null,"small_sample":true}"#.utf8), 200)
        })
        let result = await reporter.report(score: 75, dims: dims, appVersion: "1.0", now: now)
        XCTAssertNil(result)
        XCTAssertNil(defaults.data(forKey: "scoreResult"))
        let store = SnapshotStore(defaults: defaults)
        store.shareAnonymousScore = true
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(defaults.string(forKey: "anonDeviceToken"))))
        XCTAssertTrue(SnapshotStore(defaults: defaults).shareAnonymousScore)
        store.shareAnonymousScore = false
        XCTAssertNil(store.ranking)
        XCTAssertFalse(SnapshotStore(defaults: defaults).shareAnonymousScore)
    }

    func testDimensionDecodeAndProGating() throws {
        let json = Data(#"{"score_version":"1","total":25,"rank":13,"percentile":50,"small_sample":false,"dims":{"routing":{"rank":5,"percentile":80},"timing":{"rank":13,"percentile":50},"context":{"rank":1,"percentile":100},"leverage":{"rank":25,"percentile":0}}}"#.utf8)
        let result = try JSONDecoder().decode(AppScoreOut.self, from: json)
        XCTAssertTrue(result.isValid)
        XCTAssertNil(ProFeatures(isPro: false).dimensionCaption(result, key: "routing", locale: "zh"))
        XCTAssertEqual(ProFeatures(isPro: true).dimensionCaption(result, key: "routing", locale: "zh"), "击败 80%")
        XCTAssertEqual(ProFeatures(isPro: true).dimensionCaption(result, key: "timing", locale: "en"), "Beat 50%")
        XCTAssertEqual(ProFeatures(isPro: true).dimensionCaption(result, key: "leverage", locale: "zh"), "击败 0%")
        XCTAssertNil(ProFeatures(isPro: true).dimensionCaption(nil, key: "routing", locale: "zh"))
        let early = try JSONDecoder().decode(AppScoreOut.self, from: Data(#"{"score_version":"1","total":3,"rank":2,"percentile":null,"small_sample":true,"dims":{"routing":{"rank":2,"percentile":null},"timing":{"rank":1,"percentile":null},"context":{"rank":1,"percentile":null},"leverage":{"rank":3,"percentile":null}}}"#.utf8))
        XCTAssertEqual(ProFeatures(isPro: true).dimensionCaption(early, key: "routing", locale: "zh"), "第 2 名")
        XCTAssertEqual(ProFeatures(isPro: true).dimensionCaption(early, key: "routing", locale: "en"), "#2")
        let old = AppScoreOut(total: 25, rank: 13, percentile: 50, small_sample: false)
        XCTAssertNil(ProFeatures(isPro: true).dimensionCaption(old, key: "routing", locale: "zh"))
        for invalid in ["\"rank\":5,\"percentile\":101", "\"rank\":0,\"percentile\":80"] {
            let changed = String(decoding: json, as: UTF8.self).replacingOccurrences(of: "\"rank\":5,\"percentile\":80", with: invalid)
            XCTAssertFalse(try JSONDecoder().decode(AppScoreOut.self, from: Data(changed.utf8)).isValid)
        }
    }

    @MainActor func testDimensionRingsRenderRankingOnlyForPro() throws {
        let ranking = try JSONDecoder().decode(AppScoreOut.self, from: Data(#"{"score_version":"1","total":25,"rank":13,"percentile":50,"small_sample":false,"dims":{"routing":{"rank":5,"percentile":80},"timing":{"rank":13,"percentile":50},"context":{"rank":1,"percentile":100},"leverage":{"rank":25,"percentile":0}}}"#.utf8))
        for locale in ["zh", "en"] {
            let dimensions = [Dimension(key: "routing", label: locale == "zh" ? "模型调度" : "Routing", score: 80)]
            func image(pro: Bool, ranking: AppScoreOut?) throws -> NSImage {
                let renderer = ImageRenderer(content: DimensionRings(dimensions: dimensions, ranking: ranking,
                    features: ProFeatures(isPro: pro), locale: locale).frame(width: 408))
                return try XCTUnwrap(renderer.nsImage)
            }
            let free = try image(pro: false, ranking: ranking)
            let pro = try image(pro: true, ranking: ranking)
            XCTAssertGreaterThan(pro.size.height, free.size.height)
            XCTAssertEqual(try image(pro: true, ranking: nil).size.height, free.size.height)
        }
    }

    @MainActor func testInvalidCoverageHidesPreviousRankAndDoesNotReport() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "shareAnonymousScore")
        var calls = 0
        let reporter = ScoreReporter(defaults: defaults, transport: { _ in
            calls += 1
            return (Data(#"{"score_version":"1","total":25,"rank":13,"percentile":50,"small_sample":false}"#.utf8), 200)
        })
        let valid = try EngineRunner.decode(Data(#"{"schema":3,"overall":{"score_version":"1","score":80,"tier":"A"},"dimensions":[{"key":"routing","label":"Routing","score":80},{"key":"timing","label":"Timing","score":80},{"key":"context","label":"Context","score":80},{"key":"leverage","label":"Leverage","score":80}]}"#.utf8), status: 0)
        let unknown = try EngineRunner.decode(Data(#"{"schema":3,"overall":{"score_version":"1","score":null,"tier":null,"availability":"unavailable"},"dimensions":[]}"#.utf8), status: 0)
        let store = SnapshotStore(defaults: defaults, load: { _, _ in valid }, scoreReporter: reporter)
        await store.refresh()?.value
        XCTAssertEqual(store.ranking?.percentile, 50)
        XCTAssertEqual(calls, 1)
        store.load = { _, _ in unknown }
        await store.refresh()?.value
        XCTAssertEqual(calls, 1)
        XCTAssertNil(store.ranking)
    }

    @MainActor func testVersionedEndpointRejectsMismatchAndLegacyCache() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "shareAnonymousScore")
        defaults.set(Data(#"{"total":25,"rank":13,"percentile":50,"small_sample":false}"#.utf8), forKey: "scoreResult")
        defaults.set(now, forKey: "scoreResultAt")
        var calls = 0
        let reporter = ScoreReporter(defaults: defaults, endpoint: URL(string: "https://local.test/v1/score")!, transport: { request in
            calls += 1
            XCTAssertEqual(request.url?.path, "/v1/score/1")
            return (Data(#"{"score_version":"different","total":25,"rank":13,"percentile":50,"small_sample":false}"#.utf8), 200)
        })
        XCTAssertNil(reporter.cached(now: now))
        let result = await reporter.report(score: 75, dims: dims, appVersion: "1.0", now: now)
        XCTAssertNil(result)
        XCTAssertNil(reporter.cached(now: now))
        XCTAssertEqual(calls, 1)
    }

    @MainActor func testVersionChangesNeverReuseCachedComparisonOrBypassDailyLimit() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "shareAnonymousScore")
        var calls = 0
        let reporter = ScoreReporter(defaults: defaults, transport: { request in
            calls += 1
            let version = request.url!.lastPathComponent
            return (Data("{\"score_version\":\"\(version)\",\"total\":20,\"rank\":2,\"percentile\":95,\"small_sample\":false}".utf8), 200)
        })
        let first = await reporter.report(score: 75, dims: dims, appVersion: "1", now: now)
        XCTAssertEqual(first?.score_version, "1")
        XCTAssertNil(reporter.cached(scoreVersion: "2", now: now))
        let sameDay = await reporter.report(score: 75, dims: dims, appVersion: "1", scoreVersion: "2", now: now)
        XCTAssertNil(sameDay)
        XCTAssertEqual(calls, 1)
        let nextDay = await reporter.report(score: 75, dims: dims, appVersion: "1", scoreVersion: "2", now: now.addingTimeInterval(86400))
        XCTAssertEqual(nextDay?.score_version, "2")
        XCTAssertEqual(calls, 2)
        XCTAssertNil(reporter.cached(scoreVersion: "1", now: now.addingTimeInterval(86400)))
    }

    @MainActor func testStoreHidesMismatchedVersionAndExplainsWhy() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "shareAnonymousScore")
        let reporter = ScoreReporter(defaults: defaults, transport: { _ in
            (Data(#"{"score_version":"older","total":20,"rank":2,"percentile":95,"small_sample":false}"#.utf8), 200)
        })
        let result = try EngineRunner.decode(Data(#"{"schema":3,"overall":{"score_version":"1","score":80,"tier":"A"},"dimensions":[{"key":"routing","label":"Routing","score":80},{"key":"timing","label":"Timing","score":80},{"key":"context","label":"Context","score":80},{"key":"leverage","label":"Leverage","score":80}]}"#.utf8), status: 0)
        let store = SnapshotStore(defaults: defaults, load: { _, _ in result }, scoreReporter: reporter)
        await store.refresh()?.value
        XCTAssertNil(store.ranking)
        XCTAssertEqual(store.rankingCaption(locale: "zh"), "评分版本不同，暂不比较")
        XCTAssertEqual(store.rankingCaption(locale: "en"), "Scoring versions differ; comparison unavailable")
    }

    func testRankingStrings() {
        let early = AppScoreOut(total: 3, rank: 2, percentile: nil, small_sample: true)
        XCTAssertEqual(early.caption(locale: "zh"), "早期排名：3 人中第 2 名")
        XCTAssertEqual(early.caption(locale: "en"), "Early ranking: #2 of 3")
        let ranked = AppScoreOut(total: 25, rank: 13, percentile: 50, small_sample: false)
        XCTAssertEqual(ranked.caption(locale: "zh"), "击败全球 50% 的 AI 用户")
        XCTAssertEqual(ranked.caption(locale: "en"), "You beat 50% of AI users worldwide")
        XCTAssertEqual(ranked.participationCaption(locale: "zh"), "25 个安装参与")
        XCTAssertEqual(ranked.participationCaption(locale: "en"), "25 installations participating")
        XCTAssertEqual(AppScoreOut.sampleLimitation(locale: "zh"), "基于自愿参与的安装样本，不代表所有 AI 用户；同一人可能有多个安装")
        XCTAssertEqual(AppScoreOut.sampleLimitation(locale: "en"), "Based on opt-in installations, not all AI users. One person may have multiple installations")
    }
}
