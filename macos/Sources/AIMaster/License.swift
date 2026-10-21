import Foundation
import CryptoKit

enum License {
    static let publicKeyBase64 = "REPLACE_PUBLIC_KEY"
    static let checkoutURL = "REPLACE_WAFFO_CHECKOUT"

    struct Payload: Decodable {
        let v: Int
        let lic: String
        let plan: String
        let iat: String
        let exp: String
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
              validDate(payload.iat), validDate(payload.exp), payload.iat <= payload.exp else { throw Failure.format }
        guard payload.exp >= today else { throw Failure.expired }
        return payload
    }
}
