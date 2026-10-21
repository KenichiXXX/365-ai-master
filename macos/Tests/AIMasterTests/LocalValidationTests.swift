import XCTest
import CryptoKit
@testable import AIMaster

@MainActor
final class LocalValidationTests: XCTestCase {
    func testOnlyExplicitForegroundOpenRecordsReturnAndFreeAllowsSharing() async throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures"))
        let result = try EngineRunner.decode(Data(contentsOf: fixture), status: 0)
        let calls = LocalCommandRecorder()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = SnapshotStore(defaults: defaults, load: { _, _ in result })
        store.actionCommand = { arguments in calls.append(arguments); return true }
        await store.refresh()?.value
        store.resumeEntitlement()
        XCTAssertEqual(calls.values, [])
        await store.recordLocalEvent(.foregroundOpen).value
        await store.recordLocalEvent(.sharePreview).value
        XCTAssertEqual(calls.values, [["local-event", "foreground_open", "--result", "ok"],
                                     ["local-event", "share_preview", "--result", "ok"]])
        XCTAssertFalse(store.isPro)
        XCTAssertNotNil(ShareCardInput.from(result.snapshot, includeScore: false))
        store.checkoutReturned()
        XCTAssertFalse(store.isPro)
    }

    func testShareAndFeedbackRemainAvailableAfterTrialAndLicenseExpiry() async throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures"))
        let result = try EngineRunner.decode(Data(contentsOf: fixture), status: 0)
        var clock = Date(timeIntervalSince1970: 1_790_000_000)
        var trialData: Data?
        let trial = ProTrial(clock: { clock }, read: { trialData }, write: { trialData = $0 })
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = SnapshotStore(defaults: defaults, load: { _, _ in result }, proTrial: trial)
        store.actionCommand = { _ in true }
        store.startProTrial()
        XCTAssertTrue(store.isPro)
        clock.addTimeInterval(ProTrial.duration + 1)
        store.resumeEntitlement()
        XCTAssertFalse(store.isPro)
        XCTAssertNotNil(ShareCardInput.from(result.snapshot, includeScore: false))
        var feedback = FeedbackDraft.from(result.snapshot)
        feedback.preview()
        XCTAssertNotNil(feedback.copyText)
        await store.recordLocalEvent(.shareCopy).value
        let signer = Curve25519.Signing.PrivateKey()
        let payload = try JSONSerialization.data(withJSONObject: ["v": 1, "lic": "abcdefghijklmnop", "plan": "pro",
                                                                 "iat": "2024-01-01", "exp": "2025-01-01"])
        func encode(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let expiredDefaults = UserDefaults(suiteName: UUID().uuidString)!
        expiredDefaults.set("AIM1.\(encode(payload)).\(encode(try signer.signature(for: payload)))", forKey: "licenseKey")
        let expired = SnapshotStore(defaults: expiredDefaults, load: { _, _ in result },
            licensePublicKeyBase64: signer.publicKey.rawRepresentation.base64EncodedString())
        expired.actionCommand = { _ in true }
        await expired.licenseRefreshTask?.value
        XCTAssertNotNil(expired.signedLicense)
        XCTAssertFalse(expired.isPro)
        XCTAssertNotNil(ShareCardInput.from(result.snapshot, includeScore: false))
        await expired.recordLocalEvent(.sharePreview).value
    }

    func testFeedbackMustBePreviewedAndChangingReasonInvalidatesCopy() throws {
        var draft = FeedbackDraft(appVersion: "1.0", schema: 3, coverage: [.unsupported: 2], attempts: 2, observations: 1)
        XCTAssertNil(draft.copyText)
        draft.preview()
        let text = try XCTUnwrap(draft.copyText)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["appVersion", "schema", "coverage", "reason", "attempts", "observations"])
        XCTAssertEqual(object["attempts"] as? Int, 2)
        draft.reason = .noProject
        XCTAssertNil(draft.copyText)
        draft.preview()
        XCTAssertTrue(draft.copyText!.contains("no_project"))
        let rejected = FeedbackDraft(appVersion: "/private/license-secret", schema: 3, coverage: [:], attempts: 0, observations: 0)
        XCTAssertEqual(rejected.appVersion, "unknown")
    }
}

private final class LocalCommandRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [[String]] = []
    var values: [[String]] { lock.lock(); defer { lock.unlock() }; return storage }
    func append(_ value: [String]) { lock.lock(); defer { lock.unlock() }; storage.append(value) }
}
