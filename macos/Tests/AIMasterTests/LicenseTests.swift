import XCTest
import CryptoKit
import SwiftUI
@testable import AIMaster

final class LicenseTests: XCTestCase {
    private let signingKey = Curve25519.Signing.PrivateKey()
    private var publicKey: String { signingKey.publicKey.rawRepresentation.base64EncodedString() }
    private func key(exp: String = "2027-10-21", plan: String = "pro", version: Int = 1,
                     iat: String = "2026-10-21") throws -> String {
        let payload = Data("{\"v\":\(version),\"lic\":\"abcdefghijklmnop\",\"plan\":\"\(plan)\",\"iat\":\"\(iat)\",\"exp\":\"\(exp)\"}".utf8)
        return "AIM1.\(encode(payload)).\(encode(try signingKey.signature(for: payload)))"
    }
    private func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private func assertFailure(_ key: String, _ error: License.Failure) {
        XCTAssertThrowsError(try License.verify(key, publicKeyBase64: publicKey, today: "2026-10-21")) {
            XCTAssertEqual($0 as? License.Failure, error)
        }
    }
    func testValidSignatureAndInclusiveExpiry() throws {
        let payload = try License.verify(key(exp: "2026-10-21"), publicKeyBase64: publicKey, today: "2026-10-21")
        XCTAssertEqual(payload.exp, "2026-10-21")
        XCTAssertEqual(payload.lic, "abcdefghijklmnop")
    }
    func testRejectsMalformedTamperedExpiredAndUnsupportedKeys() throws {
        for malformed in ["", "AIM1.x.y", "AIM2.x.y", "AIM1.@@.@@", try key() + ".extra"] {
            assertFailure(malformed, .format)
        }
        assertFailure(try key(exp: "2026-10-20", iat: "2025-10-21"), .expired)
        assertFailure(try key(plan: "free"), .format)
        assertFailure(try key(version: 2), .format)
        assertFailure(try key(exp: "2027-02-30"), .format)
        assertFailure(try key(iat: "bad"), .format)
        let valid = try key()
        let parts = valid.split(separator: ".")
        let altered = Data("{\"v\":1,\"lic\":\"abcdefghijklmnop\",\"plan\":\"pro\",\"iat\":\"2026-10-21\",\"exp\":\"2099-01-01\"}".utf8)
        assertFailure("AIM1.\(encode(altered)).\(parts[2])", .signature)
        XCTAssertThrowsError(try License.verify(valid, publicKeyBase64: "REPLACE_PUBLIC_KEY", today: "2026-10-21"))
        XCTAssertEqual(License.Failure.format.message(locale: "zh"), "格式不对")
        XCTAssertEqual(License.Failure.signature.message(locale: "zh"), "签名无效")
        XCTAssertEqual(License.Failure.expired.message(locale: "zh"), "已过期")
    }
    @MainActor func testActivationPersistenceReverificationAndURL() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = SnapshotStore(defaults: defaults, licensePublicKeyBase64: publicKey)
        XCTAssertFalse(store.isPro)
        let valid = try key(exp: "2099-01-01")
        XCTAssertTrue(store.activateLicense(valid))
        XCTAssertTrue(store.isPro)
        XCTAssertEqual(defaults.string(forKey: "licenseKey"), valid)
        XCTAssertTrue(SnapshotStore(defaults: defaults, licensePublicKeyBase64: publicKey).isPro)
        XCTAssertFalse(store.activateLicense("bad"))
        XCTAssertTrue(store.isPro, "Invalid input must preserve the existing license")
        defaults.set("bad", forKey: "licenseKey")
        defaults.set(true, forKey: "isPro")
        XCTAssertFalse(SnapshotStore(defaults: defaults, licensePublicKeyBase64: publicKey).isPro)
        defaults.set(try key(exp: "2000-01-01", iat: "1999-01-01"), forKey: "licenseKey")
        XCTAssertFalse(SnapshotStore(defaults: defaults, licensePublicKeyBase64: publicKey).isPro)
        XCTAssertFalse(store.handleActivationURL(URL(string: "https://activate?key=bad")!))
        XCTAssertFalse(store.handleActivationURL(URL(string: "aimaster365://other?key=bad")!))
        var url = URLComponents(string: "aimaster365://activate")!
        url.queryItems = [URLQueryItem(name: "key", value: valid)]
        XCTAssertTrue(store.handleActivationURL(url.url!))
        XCTAssertTrue(store.isPro)
        XCTAssertFalse(store.handleActivationURL(URL(string: "aimaster365://activate")!))
    }
    @MainActor func testValidLicenseSupersedesTrialEvenAfterTerminalTrialExpiry() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var state: Data?
        let trial = ProTrial(clock: { now }, read: { state }, write: { state = $0 })
        let store = SnapshotStore(defaults: defaults, licensePublicKeyBase64: publicKey, proTrial: trial)
        store.startProTrial()
        guard case .trial = store.entitlement else { return XCTFail("Trial should be active") }
        XCTAssertTrue(store.activateLicense(try key(exp: "2099-01-01")))
        guard case .licensed(let license) = store.entitlement else { return XCTFail("License takes precedence") }
        XCTAssertEqual(license.lic, "abcdefghijklmnop")
        now += 14 * 86400
        store.resumeEntitlement()
        XCTAssertEqual(store.trialStatus, .expired(.deadline))
        XCTAssertTrue(store.isPro)
        let terminal = state
        store.startProTrial()
        XCTAssertEqual(state, terminal)
        defaults.set("invalid", forKey: "licenseKey")
        store.resumeEntitlement()
        XCTAssertFalse(store.isPro)
        XCTAssertEqual(state, terminal)
        defaults.set("corrupt", forKey: ProTrial.storageKey)
        let corrupted = SnapshotStore(defaults: defaults)
        XCTAssertFalse(corrupted.isPro)
        XCTAssertEqual(corrupted.trialStatus, .expired(.corrupt))
        corrupted.startProTrial()
        XCTAssertFalse(corrupted.isPro)
    }

    @MainActor func testPaywallRendersInBothLanguagesAndLicenseStates() throws {
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, licensePublicKeyBase64: publicKey)
        for pro in [false, true] {
            if pro { XCTAssertTrue(store.activateLicense(try key(exp: "2099-01-01"))) }
            for zh in [true, false] {
                let view = ProSettingsSection(store: store, zh: zh).padding(20).frame(width: 380)
                    .background(Color(nsColor: .windowBackgroundColor))
                let hosting = NSHostingView(rootView: view)
                hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
                hosting.layoutSubtreeIfNeeded()
                XCTAssertEqual(hosting.bounds.width, 380)
                XCTAssertGreaterThan(hosting.bounds.height, 100)
                XCTAssertLessThan(hosting.bounds.height, 1500)
                let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                if let out = ProcessInfo.processInfo.environment["RENDER_OUT"] {
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        .write(to: URL(fileURLWithPath: "\(out)-paywall-\(zh ? "zh" : "en")-\(pro ? "pro" : "free").png"))
                }
            }
        }
    }

    private func containsText(_ text: Text, in value: Any) -> Bool {
        if let candidate = value as? Text { return candidate == text }
        return Mirror(reflecting: value).children.contains { containsText(text, in: $0.value) }
    }
    @MainActor func testPaywallShowsHonestPlaceholderAndActivatedExpiry() throws {
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, licensePublicKeyBase64: publicKey)
        let free = ProSettingsSection(store: store, zh: true).body
        XCTAssertTrue(PurchaseTerms.lines(locale: "zh").contains("Pro 创始价 USD $12/年，每年自动续费"))
        XCTAssertTrue(containsText(Text(verbatim: "支付接入待验证，暂不可购买"), in: free))
        XCTAssertFalse(containsText(Text("去付款"), in: free))
        for item in ["成长曲线：30 天分数走势、本周比上周", "每周复盘：本地生成一页周报，可选开启提醒", "技能图鉴随时选学、完整榜单 Top 20", "四维分别排名"] {
            XCTAssertTrue(containsText(Text(LocalizedStringKey(item)), in: free))
        }
        XCTAssertTrue(store.activateLicense(try key(exp: "2099-01-01")))
        XCTAssertTrue(containsText(Text(verbatim: "本地激活码有效至 " + DisplayDate.short("2099-01-01", locale: "zh", year: true)), in: ProSettingsSection(store: store, zh: true).body))
    }
}
