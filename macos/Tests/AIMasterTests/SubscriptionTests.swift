import XCTest
import CryptoKit
@testable import AIMaster

@MainActor
final class SubscriptionTests: XCTestCase {
    private let signer = Curve25519.Signing.PrivateKey()
    private var publicKey: String { signer.publicKey.rawRepresentation.base64EncodedString() }
    private var now = ISO8601DateFormatter().date(from: "2026-10-21T12:00:00Z")!
    private func key(exp: String = "2026-10-21", lic: String = "abcdefghijklmnop") throws -> String {
        let bytes = try JSONSerialization.data(withJSONObject: ["v": 1, "lic": lic, "plan": "pro",
            "iat": "2025-10-21", "exp": exp])
        func encode(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        return "AIM1.\(encode(bytes)).\(encode(try signer.signature(for: bytes)))"
    }
    private func defaults() -> UserDefaults { UserDefaults(suiteName: UUID().uuidString)! }
    private func response(_ key: String, autoRenew: Bool = true) -> LicenseRefreshResult {
        .active(key: key, autoRenew: autoRenew, paidThrough: "2027-10-22T00:00:00Z")
    }

    func testExpiredProofRemainsAuthenticButIsNotEntitlement() throws {
        let proof = try key(exp: "2026-10-20")
        XCTAssertEqual(try License.authenticate(proof, publicKeyBase64: publicKey).lic, "abcdefghijklmnop")
        XCTAssertThrowsError(try License.verify(proof, publicKeyBase64: publicKey, today: "2026-10-21"))
    }

    func testRenewalAndExpiredRecoveryAtomicallyReplaceSameLicenseOnly() async throws {
        for expired in [false, true] {
            let prefs = defaults()
            let old = try key(exp: expired ? "2026-10-20" : "2026-10-21")
            let fresh = try key(exp: "2027-10-21")
            prefs.set(old, forKey: "licenseKey")
            prefs.set(true, forKey: "autoRefreshLicense")
            var requests: [LicenseRefreshRequest] = []
            let fake = FakeLicenseTransport { request in
                requests.append(request)
                return self.response(fresh, autoRenew: false)
            }
            let renewal = LicenseRenewal(defaults: prefs, transport: fake, publicKey: publicKey, clock: { self.now })
            await renewal.refresh()
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests.first?.key, old)
            XCTAssertEqual(requests.first?.lic, "abcdefghijklmnop")
            XCTAssertEqual(prefs.string(forKey: "licenseKey"), fresh)
            XCTAssertEqual(renewal.state, .active(autoRenew: false, paidThrough: "2027-10-22T00:00:00Z"))
            XCTAssertEqual(try License.verify(fresh, publicKeyBase64: publicKey, today: "2026-10-22").exp, "2027-10-21")
            XCTAssertNil(prefs.string(forKey: "anonDeviceToken"))
        }
    }

    func testThrottleExplicitRetryCoalescingAndDailyWindow() async throws {
        let prefs = defaults()
        prefs.set(try key(), forKey: "licenseKey")
        prefs.set(true, forKey: "autoRefreshLicense")
        var calls = 0
        var release: CheckedContinuation<Void, Never>?
        let fake = FakeLicenseTransport { _ in
            calls += 1
            if calls == 1 { await withCheckedContinuation { release = $0 } }
            return .unavailable
        }
        let renewal = LicenseRenewal(defaults: prefs, transport: fake, publicKey: publicKey, clock: { self.now })
        let first = Task { await renewal.refresh() }
        while release == nil { await Task.yield() }
        let concurrent = Task { await renewal.refresh(explicit: true) }
        await Task.yield()
        XCTAssertEqual(calls, 1)
        release?.resume()
        await first.value
        await concurrent.value
        await renewal.refresh()
        XCTAssertEqual(calls, 1)
        await renewal.refresh(explicit: true)
        await renewal.refresh(explicit: true)
        XCTAssertEqual(calls, 2, "One explicit retry per 24 hour window")
        self.now += 86400
        await renewal.refresh()
        XCTAssertEqual(calls, 3)
        self.now -= 172800
        await renewal.refresh()
        XCTAssertEqual(calls, 3, "Clock rollback must not reset throttle")
    }

    func testOffFreeTrialFarExpiryAndInvalidProofNeverAutoRequest() async throws {
        for variant in ["off", "free", "trial", "far", "invalid"] {
            let prefs = defaults()
            prefs.set(variant != "off", forKey: "autoRefreshLicense")
            if variant == "off" { prefs.set(try key(), forKey: "licenseKey") }
            if variant == "far" { prefs.set(try key(exp: "2027-10-21"), forKey: "licenseKey") }
            if variant == "invalid" { prefs.set("tampered", forKey: "licenseKey") }
            if variant == "trial" { prefs.set(true, forKey: "isPro") }
            let fake = FakeLicenseTransport { _ in XCTFail("Unexpected request: \(variant)"); return .unavailable }
            await LicenseRenewal(defaults: prefs, transport: fake, publicKey: publicKey, clock: { self.now }).refresh()
        }
    }

    func testTamperWrongLicenseExpiredResponseOutageAndManualPreserveProof() async throws {
        let old = try key()
        let results: [LicenseRefreshResult] = [.active(key: "bad", autoRenew: true, paidThrough: "2027-10-22T00:00:00Z"),
            response(try key(exp: "2027-10-21", lic: "ponmlkjihgfedcba")), response(try key(exp: "2026-10-20")),
            .unavailable, .pending, .expired, .revoked, .manual]
        for result in results {
            let prefs = defaults()
            prefs.set(old, forKey: "licenseKey")
            prefs.set(true, forKey: "autoRefreshLicense")
            let fake = FakeLicenseTransport { _ in result }
            let renewal = LicenseRenewal(defaults: prefs, transport: fake, publicKey: publicKey, clock: { self.now })
            await renewal.refresh()
            XCTAssertEqual(prefs.string(forKey: "licenseKey"), old)
            XCTAssertNoThrow(try License.verify(old, publicKeyBase64: publicKey, today: "2026-10-21"))
            XCTAssertThrowsError(try License.verify(old, publicKeyBase64: publicKey, today: "2026-10-22"))
        }
    }

    func testExpiredImportCanRecoverAndLicenseTimerExpiresOffline() async throws {
        let prefs = defaults()
        let store = SnapshotStore(defaults: prefs, licensePublicKeyBase64: publicKey,
            licenseTransport: FakeLicenseTransport { _ in .unavailable }, licenseClock: { self.now })
        XCTAssertTrue(store.activateLicense(try key(exp: "2026-10-20")))
        XCTAssertFalse(store.isPro)
        XCTAssertNotNil(store.signedLicense)
        XCTAssertTrue(store.activateLicense(try key()))
        XCTAssertTrue(store.isPro)
        XCTAssertNotNil(store.licenseExpiryTimer)
        now += 86400
        store.licenseExpiryTimer?.fire()
        await Task.yield()
        XCTAssertFalse(store.isPro)
        XCTAssertNotNil(store.signedLicense)
    }

    func testManualKeyIsNotAutomaticallyPolledAgainAndRestartThrottlePersists() async throws {
        let prefs = defaults()
        let proof = try key()
        prefs.set(proof, forKey: "licenseKey")
        prefs.set(true, forKey: "autoRefreshLicense")
        var calls = 0
        let fake = FakeLicenseTransport { _ in calls += 1; return .manual }
        let renewal = LicenseRenewal(defaults: prefs, transport: fake, publicKey: publicKey, clock: { self.now })
        await renewal.refresh()
        XCTAssertEqual(renewal.state, .manual)
        now += 86400
        await renewal.refresh()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(prefs.string(forKey: "licenseKey"), proof)
        await renewal.refresh(explicit: true)
        XCTAssertEqual(calls, 2)
        let restarted = LicenseRenewal(defaults: prefs, transport: fake, publicKey: publicKey, clock: { self.now })
        await restarted.refresh()
        XCTAssertEqual(calls, 2)
    }

    func testNewImportClearsPriorManualStatusAndExpiryShowsRecovery() async throws {
        let prefs = defaults()
        let store = SnapshotStore(defaults: prefs, licensePublicKeyBase64: publicKey,
            licenseTransport: FakeLicenseTransport { _ in .manual }, licenseClock: { self.now })
        await store.licenseRefreshTask?.value
        XCTAssertTrue(store.activateLicense(try key()))
        await store.licenseRefreshTask?.value
        await store.refreshLicense(explicit: true).value
        XCTAssertEqual(store.renewalState, .manual)
        XCTAssertTrue(store.activateLicense(try key(exp: "2027-10-21")))
        await store.licenseRefreshTask?.value
        XCTAssertEqual(store.renewalState, .idle)
        XCTAssertTrue(store.activateLicense(try key(exp: "2026-10-20")))
        await store.licenseRefreshTask?.value
        XCTAssertEqual(store.renewalState, .expired)
    }

    func testWireContractAndBoundedResponse() async throws {
        let proof = try key()
        let fresh = try key(exp: "2027-10-21")
        let transport = LicenseServiceTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "https://365aimaster-ranking.viberankworkersdev.workers.dev/v1/license/refresh")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertEqual(request.timeoutInterval, 15)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
            XCTAssertEqual(body, ["lic": "abcdefghijklmnop", "key": proof])
            return (try JSONSerialization.data(withJSONObject: ["status": "active", "key": fresh,
                "auto_renew": true, "paid_through": "2027-10-22T00:00:00Z"]), 200)
        }
        let result = await transport.refresh(.init(lic: "abcdefghijklmnop", key: proof))
        XCTAssertEqual(result, response(fresh))
        for (data, status) in [(Data(repeating: 65, count: 8193), 200), (Data("{}".utf8), 200),
                               (Data("{\"status\":\"active\"}".utf8), 503)] {
            let fake = LicenseServiceTransport { _ in (data, status) }
            let invalid = await fake.refresh(.init(lic: "abcdefghijklmnop", key: proof))
            XCTAssertEqual(invalid, .unavailable)
        }
    }

    func testStoreExpiryOfflineKeepsSnapshotAndLaunchDoesNotBlockAnalysis() async throws {
        let prefs = defaults()
        prefs.set(try key(), forKey: "licenseKey")
        prefs.set(true, forKey: "autoRefreshLicense")
        var release: CheckedContinuation<Void, Never>?
        let fake = FakeLicenseTransport { _ in
            await withCheckedContinuation { release = $0 }
            return .unavailable
        }
        let fixture = try EngineRunner.decode(Data(#"{"schema":3}"#.utf8), status: 0)
        let store = SnapshotStore(defaults: prefs, load: { _, _ in fixture }, licensePublicKeyBase64: publicKey,
            licenseTransport: fake, licenseClock: { self.now })
        await store.refresh()?.value
        XCTAssertTrue(store.isPro)
        XCTAssertEqual(store.snapshotJSON, fixture.json)
        while release == nil { await Task.yield() }
        self.now += 86400
        store.resumeEntitlement()
        XCTAssertFalse(store.isPro)
        XCTAssertEqual(store.snapshotJSON, fixture.json)
        XCTAssertNotNil(prefs.string(forKey: "licenseKey"))
        release?.resume()
        await store.licenseRefreshTask?.value
        XCTAssertEqual(store.renewalState, .unavailable)
    }

    func testBrowserReturnWithoutProofStaysPendingAcrossForeground() async {
        let store = SnapshotStore(defaults: defaults(), licenseTransport: FakeLicenseTransport { _ in
            XCTFail("Browser return cannot authenticate renewal")
            return .unavailable
        })
        await store.licenseRefreshTask?.value
        store.checkoutReturned()
        store.resumeEntitlement()
        await store.licenseRefreshTask?.value
        XCTAssertEqual(store.renewalState, .pending)
        XCTAssertFalse(store.isPro)
    }

    func testCheckoutRequiresVerifiedConfigTermsAndSeparateSourceConsent() throws {
        XCTAssertNil(PurchaseConfiguration.unavailable.checkout(source: nil))
        XCTAssertNil(PurchaseConfiguration.unavailable.managementURL)
        let bad = PurchaseConfiguration(subscriptionCheckout: URL(string: "https://attacker.example/pay"),
            management: URL(string: "https://attacker.example/manage"), allowedHosts: ["merchant.example"],
            verifiedIntegration: true, verifiedTerms: true)
        XCTAssertNil(bad.checkout(source: nil))
        XCTAssertNil(bad.managementURL)
        let config = PurchaseConfiguration(subscriptionCheckout: URL(string: "https://merchant.example/pay"),
            management: URL(string: "https://merchant.example/manage"), allowedHosts: ["merchant.example"],
            verifiedIntegration: true, verifiedTerms: true)
        var opened: [URL] = []
        XCTAssertFalse(config.openCheckout(termsPresented: false, source: nil, open: { opened.append($0) }))
        XCTAssertTrue(config.openCheckout(termsPresented: true, source: nil, open: { opened.append($0) }))
        XCTAssertNil(opened.first?.query)
        for locale in ["zh", "en"] {
            let terms = PurchaseTerms.lines(locale: locale).joined(separator: "\n")
            XCTAssertTrue(terms.contains("USD $12"))
            XCTAssertTrue(terms.contains(locale == "zh" ? "每年自动续费" : "renews automatically every year"))
            XCTAssertTrue(terms.contains(locale == "zh" ? "不会自动转为付费" : "never automatically becomes paid"))
            XCTAssertGreaterThanOrEqual(PurchaseTerms.lines(locale: locale).count, 6)
        }
        let store = SnapshotStore(defaults: defaults())
        store.checkoutReturned()
        XCTAssertFalse(store.isPro)
        XCTAssertEqual(store.renewalState, .pending)
    }
}

@MainActor
private struct FakeLicenseTransport: LicenseTransport {
    let handler: (LicenseRefreshRequest) async -> LicenseRefreshResult
    init(_ handler: @escaping (LicenseRefreshRequest) async -> LicenseRefreshResult) { self.handler = handler }
    func refresh(_ request: LicenseRefreshRequest) async -> LicenseRefreshResult { await handler(request) }
}
