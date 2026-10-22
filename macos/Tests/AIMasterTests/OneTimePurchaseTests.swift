import XCTest
import SwiftUI
import CryptoKit
import UserNotifications
@testable import AIMaster

@MainActor
final class OneTimePurchaseTests: XCTestCase {
    func testIndependentCheckoutAvailabilityLocaleOrderAndRenewalCopy() throws {
        let host: Set<String> = ["merchant.test"]
        let subscription = URL(string: "https://merchant.test/subscription")!
        let wallet = URL(string: "https://merchant.test/wallet")!
        for (sub, once) in [(nil, nil), (subscription, nil), (nil, wallet), (subscription, wallet)] as [(URL?, URL?)] {
            let config = PurchaseConfiguration(subscriptionCheckout: sub, oneTimeCheckout: once,
                management: URL(string: "https://merchant.test/manage"), allowedHosts: host,
                verifiedIntegration: true, verifiedTerms: true)
            XCTAssertEqual(config.checkout(option: .subscription, source: nil), sub)
            XCTAssertEqual(config.checkout(option: .oneTimeAnnual, source: nil), once)
            for zh in [true, false] {
                let options = PurchaseOption.ordered(zh: zh)
                XCTAssertEqual(options.first, zh ? .oneTimeAnnual : .subscription)
                XCTAssertEqual(options.filter { config.checkout(option: $0, source: nil) != nil }.count,
                               [sub, once].compactMap { $0 }.count)
                XCTAssertTrue(PurchaseOption.subscription.title(zh: zh).contains(zh ? "每年自动续费" : "renews automatically"))
                XCTAssertTrue(PurchaseOption.oneTimeAnnual.title(zh: zh).contains(zh ? "一次付一年" : "one year"))
                let terms = PurchaseTerms.lines(locale: zh ? "zh" : "en", option: .oneTimeAnnual).joined(separator: " ")
                XCTAssertTrue(terms.contains(zh ? "不自动续费" : "does not auto-renew"))
                XCTAssertTrue(terms.contains(zh ? "到期前 7 天提醒你续费" : "7 days before expiry"))
            }
        }
        let placeholder = PurchaseConfiguration(subscriptionCheckout: subscription,
            oneTimeCheckout: URL(string: "https://placeholder.invalid/wallet"), management: nil,
            allowedHosts: host, verifiedIntegration: true, verifiedTerms: true)
        XCTAssertNil(placeholder.checkout(option: .subscription, source: nil), "Subscription needs cancellation management")
        XCTAssertNil(placeholder.checkout(option: .oneTimeAnnual, source: nil))
        let oneOnly = PurchaseConfiguration(subscriptionCheckout: nil, oneTimeCheckout: wallet, management: nil,
            allowedHosts: host, verifiedIntegration: true, verifiedTerms: true)
        var opened: [URL] = []
        XCTAssertFalse(oneOnly.openCheckout(option: .oneTimeAnnual, termsPresented: false, source: nil) { opened.append($0) })
        XCTAssertTrue(oneOnly.openCheckout(option: .oneTimeAnnual, termsPresented: true, source: nil) { opened.append($0) })
        XCTAssertEqual(opened, [wallet])
    }

    func testSignedOneTimeReminderWindowOfflineRestartAndNotificationRoute() async throws {
        let signer = Curve25519.Signing.PrivateKey()
        func key(product: String?) throws -> String {
            var object: [String: Any] = ["v": 1, "lic": "abcdefghijklmnop", "plan": "pro", "iat": "2026-01-01", "exp": "2026-12-31"]
            object["product"] = product
            let bytes = try JSONSerialization.data(withJSONObject: object)
            func b64(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
            return "AIM1.\(b64(bytes)).\(b64(try signer.signature(for: bytes)))"
        }
        var now = ISO8601DateFormatter().date(from: "2026-12-23T12:00:00Z")!
        let prefs = UserDefaults(suiteName: UUID().uuidString)!
        let center = WalletReminderCenter()
        let notifications = OneTimeRenewalNotifications(center: center, defaults: prefs, clock: { now })
        let signed = try key(product: "one_time_annual")
        let store = SnapshotStore(defaults: prefs, licensePublicKeyBase64: signer.publicKey.rawRepresentation.base64EncodedString(),
            licenseClock: { now }, oneTimeNotifications: notifications)
        store.actionCommand = { _ in true }
        XCTAssertTrue(store.activateLicense(signed))
        await store.oneTimeNotificationTask?.value
        XCTAssertNil(store.oneTimeRenewalDays)
        XCTAssertEqual(center.requests.count, 1, "Schedule one future reminder while permission is already granted")
        let trigger = try XCTUnwrap(center.requests.first?.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.day, 24)
        now += 86400
        store.resumeEntitlement()
        await store.oneTimeNotificationTask?.value
        XCTAssertEqual(store.oneTimeRenewalDays, 7)
        XCTAssertEqual(center.requests.count, 1)
        XCTAssertFalse(store.openReminder(["one_time_lic": "wrong", "one_time_exp": "2026-12-31"]))
        XCTAssertTrue(store.openReminder(center.requests[0].content.userInfo))
        XCTAssertTrue(store.showProSettings)
        XCTAssertEqual(store.selectedPurchaseOption, .oneTimeAnnual)
        let restarted = OneTimeRenewalNotifications(center: center, defaults: prefs, clock: { now })
        await restarted.schedule(license: store.signedLicense, locale: "en")
        XCTAssertEqual(center.requests.count, 1)
        now += 7 * 86400
        store.resumeEntitlement()
        XCTAssertEqual(store.oneTimeRenewalDays, 0)
        now += 86400
        store.resumeEntitlement()
        XCTAssertNil(store.oneTimeRenewalDays)
        XCTAssertTrue(store.activateLicense(try key(product: nil)))
        XCTAssertNil(store.oneTimeRenewalDays, "Old and cancelled subscription keys are not one-time purchases")
        let oneTimeProof = try License.authenticate(signed, publicKeyBase64: signer.publicKey.rawRepresentation.base64EncodedString())
        for status in [ReminderAuthorization.denied, .notDetermined] {
            let denied = WalletReminderCenter(); denied.authorization = status
            await OneTimeRenewalNotifications(center: denied, defaults: UserDefaults(suiteName: UUID().uuidString)!,
                clock: { now.addingTimeInterval(-8 * 86400) }).schedule(license: oneTimeProof, locale: "zh")
            XCTAssertTrue(denied.requests.isEmpty)
        }
    }
}

@MainActor
private final class WalletReminderCenter: OneTimeReminderCenter {
    var authorization: ReminderAuthorization = .authorized
    var requests: [UNNotificationRequest] = []
    func status() async -> ReminderAuthorization { authorization }
    func add(_ request: UNNotificationRequest) async throws { requests.append(request) }
    func remove(_ identifiers: [String]) {}
}
