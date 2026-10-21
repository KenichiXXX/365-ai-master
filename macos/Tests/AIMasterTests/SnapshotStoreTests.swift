import XCTest
import CryptoKit
@testable import AIMaster

final class SnapshotStoreTests: XCTestCase {
    func testRunnerRejectsFailureAndUnsupportedSchema() throws {
        XCTAssertThrowsError(try EngineRunner.decode(Data("{\"schema\":1,\"error\":\"ValueError\"}".utf8), status: 2))
        XCTAssertThrowsError(try EngineRunner.decode(Data("not json".utf8), status: 0))
        XCTAssertThrowsError(try EngineRunner.decode(Data("{\"schema\":4}".utf8), status: 0))
        XCTAssertThrowsError(try EngineRunner.decode(Data("{\"schema\":1,\"error\":\"ValueError\"}".utf8), status: 0))
    }

    @MainActor func testFailedRefreshKeepsSnapshotAndTimestamp() async throws {
        let url = Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures")!
        let result = try EngineRunner.decode(Data(contentsOf: url), status: 0)
        let defaults = UserDefaults(suiteName: "AIMasterTests")!
        let store = SnapshotStore(defaults: defaults, load: { _, _ in result })
        await store.refresh()?.value
        let lastRun = store.lastRun
        XCTAssertEqual(store.snapshot?.schema, 3)
        XCTAssertNotNil(lastRun)
        XCTAssertTrue(store.snapshotJSON.contains("inventory"))
        store.load = { _, _ in throw EngineError.failed(2) }
        await store.refresh()?.value
        XCTAssertEqual(store.snapshot?.schema, 3)
        XCTAssertEqual(store.lastRun, lastRun)
        XCTAssertNotNil(store.lastError)
    }

    @MainActor func testMenuBadgeUsesQuestAndNoData() throws {
        XCTAssertEqual(StatusItemController.badgeTitle(snapshot: nil), "○")
        let data = Data("{\"schema\":1,\"village\":{\"current\":null,\"rank_title\":\"Master\",\"quests\":[]}}".utf8)
        XCTAssertEqual(StatusItemController.badgeTitle(snapshot: try EngineRunner.decode(data, status: 0).snapshot), "✓")
    }
    @MainActor func testCancelBlockedScanDiscardsOutputAndRetryIsSerialized() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let good = try EngineRunner.decode(Data(#"{"schema":3,"locale":"en"}"#.utf8), status: 0)
        let partial = try EngineRunner.decode(Data(#"{"schema":3,"locale":"zh"}"#.utf8), status: 0)
        let store = SnapshotStore(defaults: defaults, load: { _, _ in good })
        await store.refresh()?.value
        let lastRun = store.lastRun
        let started = expectation(description: "blocked scan started")
        let gate = DispatchSemaphore(value: 0)
        store.load = { _, _ in started.fulfill(); gate.wait(); return partial }
        store.cancelLoad = { gate.signal() }
        let running = store.refresh()
        await fulfillment(of: [started], timeout: 3)
        XCTAssertNil(store.refresh())
        store.cancelRefresh()
        await running?.value
        XCTAssertFalse(store.isRefreshing)
        XCTAssertEqual(store.snapshot?.locale, "en")
        XCTAssertEqual(store.lastRun, lastRun)
        XCTAssertNil(store.lastError)
        store.load = { _, _ in good }
        await store.refresh()?.value
        XCTAssertFalse(store.isRefreshing)
        XCTAssertEqual(store.snapshot?.locale, "en")
    }

    @MainActor func testPhase4TrialPaymentRenewalAndAllNetworkOffPreserveLocalPractice() async throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        object["overall"] = ["score": 75, "availability": "available", "score_version": "1"]
        object["dimensions"] = ["routing", "timing", "context", "leverage"].map {
            ["key": $0, "label": $0, "score": 75, "availability": "available"] as [String: Any]
        }
        let result = try EngineRunner.decode(JSONSerialization.data(withJSONObject: object), status: 0)
        XCTAssertTrue(result.snapshot.hasEvaluableScores, "Ranking must be eligible so consent is the only network gate")
        let defaults = UserDefaults(suiteName: "phase4-" + UUID().uuidString)!
        var now = ISO8601DateFormatter().date(from: "2026-10-21T12:00:00Z")!
        var trialData: Data?
        let trial = ProTrial(clock: { now }, read: { trialData }, write: { trialData = $0 })
        let signer = Curve25519.Signing.PrivateKey()
        let lic = "abcdefghijklmnop"
        func key(_ expiry: String) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: ["v": 1, "lic": lic, "plan": "pro",
                                                                   "iat": "2026-11-04", "exp": expiry])
            func encode(_ bytes: Data) -> String {
                bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            }
            return "AIM1.\(encode(data)).\(encode(try signer.signature(for: data)))"
        }
        let initial = try key("2027-11-04")
        let renewed = try key("2028-11-04")
        var nextKey = initial
        var available = true
        var requests: [String] = []
        let transport = LicenseServiceTransport { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/license/refresh")
            let body = try XCTUnwrap(request.httpBody)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
            XCTAssertEqual(Set(object.keys), ["lic", "key"])
            XCTAssertEqual(object["lic"], lic)
            requests.append(String(decoding: body, as: UTF8.self))
            let response: [String: Any] = available
                ? ["status": "active", "key": nextKey, "auto_renew": false,
                   "paid_through": nextKey == initial ? "2027-11-05T00:00:00Z" : "2028-11-05T00:00:00Z"] : ["status": "unavailable"]
            return (try JSONSerialization.data(withJSONObject: response), available ? 200 : 503)
        }
        var scoreCalls = 0
        let scores = ScoreReporter(defaults: defaults, transport: { _ in
            scoreCalls += 1
            return (Data(), 503)
        })
        let store = SnapshotStore(defaults: defaults, load: { _, _ in result }, scoreReporter: scores,
            licensePublicKeyBase64: signer.publicKey.rawRepresentation.base64EncodedString(),
            proTrial: trial, licenseTransport: transport, licenseClock: { now })
        // Every mutation is a fake. Never let a test invoke the engine's default personal state directory.
        store.actionCommand = { _ in true }
        var publicCalls = 0
        store.downloadContent = { publicCalls += 1; return false }
        store.publicDownloads = false
        store.shareAnonymousScore = false
        store.autoRefreshLicense = false
        await store.refresh()?.value
        XCTAssertEqual(store.trialStatus, .eligible)
        XCTAssertFalse(store.isPro)
        store.startProTrial()
        store.startProTrial()
        XCTAssertTrue(store.isPro)
        now += 14 * 86400
        store.resumeEntitlement()
        XCTAssertFalse(store.isPro)
        XCTAssertEqual(store.trialStatus, .expired(.deadline))
        XCTAssertEqual(store.snapshotJSON, result.json)
        XCTAssertTrue(store.activateLicense(initial))
        await store.licenseRefreshTask?.value
        XCTAssertTrue(store.isPro)
        // All three request gates remain off even with an authentic signed subscription proof.
        await store.refreshContent().value
        await store.refresh()?.value
        store.resumeEntitlement()
        await store.licenseRefreshTask?.value
        await store.practice(id: "web_search", operation: "copy")?.value
        XCTAssertNotNil(store.feedback(for: "web_search"))
        XCTAssertEqual(publicCalls, 0)
        XCTAssertEqual(scoreCalls, 0)
        XCTAssertTrue(requests.isEmpty)
        XCTAssertNil(defaults.string(forKey: "anonDeviceToken"))
        // Explicit consent checks cancellation without revoking the already paid signed period.
        await store.refreshLicense(explicit: true).value
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(store.renewalState, .active(autoRenew: false, paidThrough: "2027-11-05T00:00:00Z"))
        XCTAssertTrue(store.isPro)
        now = ISO8601DateFormatter().date(from: "2027-11-04T12:00:00Z")!
        nextKey = renewed
        await store.refreshLicense(explicit: true).value
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(store.signedLicense?.lic, lic)
        XCTAssertEqual(defaults.string(forKey: "licenseKey"), renewed)
        // Provider outage is not cancellation; local verification works through signed expiry.
        now = ISO8601DateFormatter().date(from: "2028-11-04T12:00:00Z")!
        available = false
        await store.refreshLicense(explicit: true).value
        XCTAssertEqual(store.renewalState, .unavailable)
        XCTAssertTrue(store.isPro)
        now += 86400
        store.resumeEntitlement()
        XCTAssertFalse(store.isPro)
        XCTAssertEqual(store.snapshotJSON, result.json)
        XCTAssertEqual(defaults.string(forKey: "licenseKey"), renewed)
        await store.practice(id: "web_search", operation: "start")?.value
        XCTAssertNotNil(store.feedback(for: "web_search"))
        XCTAssertNil(store.purchaseConfiguration.checkout(source: nil))
        for body in requests {
            for forbidden in ["private-prompt-p4", "/private/project-p4", "private-argument-p4", "private-token-p4",
                              "device_token", "score", "course_source"] {
                XCTAssertFalse(body.contains(forbidden))
            }
        }
        await store.localEventTask?.value
    }

}
