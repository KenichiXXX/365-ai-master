import Foundation
import CryptoKit

enum ProEntitlement {
    case free
    case trial(until: Date)
    case licensed(License.Payload)

    var isPro: Bool {
        switch self {
        case .free: return false
        case .trial, .licensed: return true
        }
    }
}

enum License {
    static let publicKeyBase64 = "ma3DOZwYfJgnZVV9fpMY5Za0SEZV8/3/SdKzSf0ttVs="

    struct Payload: Decodable {
        let v: Int
        let lic: String
        let plan: String
        let iat: String
        let exp: String
        let product: String?

        var isOneTimeAnnual: Bool { product == "one_time_annual" }
    }

    enum Failure: Error {
        case format, signature, expired

        func message(locale: String) -> String {
            switch self {
            case .format: return locale == "zh" ? "格式不对" : "Invalid key format"
            case .signature: return locale == "zh" ? "签名无效" : "Invalid signature"
            case .expired: return locale == "zh" ? "已过期" : "Key expired"
            }
        }
    }

    static var today: String { dateFormatter().string(from: Date()) }

    private static func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }

    private static func decode(_ part: Substring) -> Data? {
        guard !part.isEmpty, part.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }) else { return nil }
        var base64 = part.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    static func verify(_ key: String, publicKeyBase64: String = publicKeyBase64,
                       today: String = today) throws -> Payload {
        let payload = try authenticate(key, publicKeyBase64: publicKeyBase64)
        guard payload.exp >= today else { throw Failure.expired }
        return payload
    }

    static func day(_ date: Date) -> String { dateFormatter().string(from: date) }

    static func authenticate(_ key: String, publicKeyBase64: String = publicKeyBase64) throws -> Payload {
        let parts = key.split(separator: ".", omittingEmptySubsequences: false)
        guard key.utf8.count <= 4096, parts.count == 3, parts[0] == "AIM1",
              let bytes = decode(parts[1]), let signature = decode(parts[2]), signature.count == 64,
              let payload = try? JSONDecoder().decode(Payload.self, from: bytes) else { throw Failure.format }
        guard let raw = Data(base64Encoded: publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
              publicKey.isValidSignature(signature, for: bytes) else { throw Failure.signature }
        let formatter = dateFormatter()
        func validDate(_ value: String) -> Bool {
            guard value.count == 10, let date = formatter.date(from: value) else { return false }
            return formatter.string(from: date) == value
        }
        guard payload.v == 1, payload.plan == "pro", payload.lic.count == 16,
              payload.lic.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0)
                  || (48...57).contains($0) || $0 == 45 || $0 == 95 }),
              (payload.product == nil || payload.product == "one_time_annual"),
              validDate(payload.iat), validDate(payload.exp), payload.iat <= payload.exp else { throw Failure.format }
        return payload
    }
}

struct LicenseRefreshRequest: Encodable {
    let lic: String
    let key: String
}

enum LicenseRefreshResult: Equatable {
    case active(key: String, autoRenew: Bool, paidThrough: String)
    case manual, pending, expired, revoked, unavailable
}

@MainActor
protocol LicenseTransport {
    func refresh(_ request: LicenseRefreshRequest) async -> LicenseRefreshResult
}

enum RenewalState: Equatable {
    case idle, refreshing, manual, pending, expired, revoked, unavailable
    case active(autoRenew: Bool, paidThrough: String)

    var messageKey: String {
        switch self {
        case .idle: return "Signed key works offline through expiry"
        case .refreshing: return "Checking subscription renewal"
        case .manual: return "Manual authorization, not a subscription"
        case .pending: return "Payment is still being confirmed"
        case .expired, .unavailable: return "Connect to check subscription renewal. Your history is preserved"
        case .revoked: return "Use your purchase receipt to contact support for license recovery"
        case .active(let autoRenew, _): return autoRenew ? "Your subscription is still active. You can refresh your activation key"
            : "Renewal cancelled by provider; access continues until the paid period ends"
        }
    }
}

@MainActor
final class LicenseRenewal {
    private let defaults: UserDefaults
    private let transport: LicenseTransport
    private let publicKey: String
    let clock: () -> Date
    private var inFlight: Task<Void, Never>?
    private(set) var state: RenewalState = .idle

    init(defaults: UserDefaults, transport: LicenseTransport, publicKey: String, clock: @escaping () -> Date) {
        self.defaults = defaults
        self.transport = transport
        self.publicKey = publicKey
        self.clock = clock
        if defaults.bool(forKey: "manualLicense") { state = .manual }
    }

    func importedKey() { state = .idle }

    func refresh(explicit: Bool = false) async {
        if let inFlight { await inFlight.value; return }
        guard explicit || defaults.bool(forKey: "autoRefreshLicense"),
              let key = defaults.string(forKey: "licenseKey"), key.utf8.count <= 768,
              let proof = try? License.authenticate(key, publicKeyBase64: publicKey) else { return }
        let now = clock()
        guard explicit || proof.exp <= License.day(now.addingTimeInterval(7 * 86400)) else { return }
        if !explicit, defaults.bool(forKey: "manualLicense") { return }
        if let last = defaults.object(forKey: "licenseAttemptAt") as? Date, now.timeIntervalSince(last) < 86400 {
            guard explicit, !defaults.bool(forKey: "licenseExplicitRetryUsed") else { return }
            defaults.set(true, forKey: "licenseExplicitRetryUsed")
        } else {
            defaults.set(now, forKey: "licenseAttemptAt")
            defaults.set(false, forKey: "licenseExplicitRetryUsed")
        }
        state = .refreshing
        let task = Task {
            let result = await transport.refresh(.init(lic: proof.lic, key: key))
            // An activation during the request owns the newer proof.
            guard defaults.string(forKey: "licenseKey") == key else { state = .idle; return }
            switch result {
            case .active(let fresh, let autoRenew, let paidThrough):
                guard let payload = try? License.verify(fresh, publicKeyBase64: publicKey, today: License.day(clock())),
                      payload.lic == proof.lic, payload.exp >= proof.exp else { state = .unavailable; return }
                defaults.set(fresh, forKey: "licenseKey")
                defaults.set(false, forKey: "manualLicense")
                state = .active(autoRenew: autoRenew, paidThrough: paidThrough)
            case .manual:
                defaults.set(true, forKey: "manualLicense")
                state = .manual
            case .pending: state = .pending
            case .expired: state = .expired
            case .revoked: state = .revoked
            case .unavailable: state = .unavailable
            }
        }
        inFlight = task
        await task.value
        inFlight = nil
    }
}

struct PurchaseConfiguration {
    let subscriptionCheckoutURL: URL?
    let oneTimeCheckoutURL: URL?
    private let management: URL?
    private let allowedHosts: Set<String>
    let verifiedIntegration: Bool
    let verifiedTerms: Bool
    static let unavailable = PurchaseConfiguration(subscriptionCheckout: nil, management: nil, allowedHosts: [],
                                                  verifiedIntegration: false, verifiedTerms: false)

    init(subscriptionCheckout: URL?, oneTimeCheckout: URL? = nil, management: URL?, allowedHosts: Set<String>, verifiedIntegration: Bool, verifiedTerms: Bool) {
        self.subscriptionCheckoutURL = subscriptionCheckout
        self.oneTimeCheckoutURL = oneTimeCheckout
        self.management = management
        self.allowedHosts = allowedHosts
        self.verifiedIntegration = verifiedIntegration
        self.verifiedTerms = verifiedTerms
    }

    private func allowed(_ url: URL?) -> URL? {
        guard let url, url.scheme == "https", let host = url.host, allowedHosts.contains(host),
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil,
              url.query == nil, !url.path.isEmpty else { return nil }
        return url
    }

    var managementURL: URL? {
        guard verifiedIntegration, verifiedTerms else { return nil }
        return allowed(management)
    }

    func checkout(option: PurchaseOption = .subscription, source: CourseSource?) -> URL? {
        guard verifiedIntegration, verifiedTerms else { return nil }
        if option == .subscription, managementURL == nil { return nil }
        guard let url = allowed(option == .subscription ? subscriptionCheckoutURL : oneTimeCheckoutURL) else { return nil }
        guard let source else { return url }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "source", value: source.code)]
        return parts?.url
    }

    @discardableResult
    func openCheckout(option: PurchaseOption = .subscription, termsPresented: Bool, source: CourseSource?, open: (URL) -> Void) -> Bool {
        guard termsPresented, let url = checkout(option: option, source: source) else { return false }
        open(url)
        return true
    }
}

enum PurchaseTerms {
    static func lines(locale: String, option: PurchaseOption = .subscription) -> [String] {
        if option == .oneTimeAnnual {
            return locale == "zh" ? ["Pro 创始价：USD $12，一次付一年（365 天），不自动续费",
                "微信支付 / 支付宝", "到期前 7 天提醒你续费", "14 天本地试用无需银行卡，不会自动转为付费",
                "激活码到期后需主动购买，不会自动扣款", "支持或退款：请通过购买凭证联系支持"]
                : ["Pro founding price: USD $12 for one year (365 days); does not auto-renew",
                   "WeChat Pay / Alipay", "We'll remind you 7 days before expiry",
                   "The 14-day local trial needs no card and never automatically becomes paid",
                   "Purchase again to continue after expiry; no automatic charge",
                   "For support or refunds, use your purchase receipt to contact support"]
        }
        return ["Pro founding price: USD $12/year, renews automatically every year",
         "To cancel, use the verified subscription-management link in your purchase receipt before the next renewal",
         "After cancellation, access continues until the paid period ends",
         "The 14-day local trial needs no card and never automatically becomes paid",
         "The signed key shows local access expiry. Billing next-renewal date is separate and confirmed by the provider",
         "For support or refunds, use your purchase receipt to contact support"]
            .map { key in localized(key, locale: locale) }
    }

    static func localized(_ key: String, locale: String) -> String {
        let language = locale == "zh" ? "zh-Hans" : "en"
        let bundle = Bundle.module.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .module
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }
}

enum PurchaseOption: String, CaseIterable, Identifiable {
    case subscription, oneTimeAnnual
    var id: String { rawValue }
    static func ordered(zh: Bool) -> [Self] { zh ? [.oneTimeAnnual, .subscription] : [.subscription, .oneTimeAnnual] }
    func title(zh: Bool) -> String {
        switch self {
        case .subscription: return zh ? "银行卡 / Apple Pay · 每年自动续费" : "Card / Apple Pay · renews automatically every year"
        case .oneTimeAnnual: return zh ? "微信支付 / 支付宝 · 一次付一年" : "WeChat Pay / Alipay · pay once for one year"
        }
    }
}
