import Foundation

private final class ScoreRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct AppScoreOut: Codable {
    let total: Int
    let rank: Int
    let percentile: Int?
    let small_sample: Bool

    var isValid: Bool {
        total > 0 && rank >= 1 && rank <= total && small_sample == (total < 20)
            && (small_sample ? percentile == nil : percentile.map { (0...100).contains($0) } == true)
    }

    func caption(locale: String) -> String {
        if small_sample {
            return locale == "zh" ? "早期排名：\(total) 人中第 \(rank) 名" : "Early ranking: #\(rank) of \(total)"
        }
        guard let percentile else { return "" }
        return locale == "zh" ? "击败了全球 \(percentile)% 的 AI 用户（\(total) 人参与）"
            : "You beat \(percentile)% of AI users (\(total) taking part)"
    }
}

@MainActor
final class ScoreReporter {
    nonisolated static let endpoint = URL(string: "https://365aimaster-ranking.viberankworkersdev.workers.dev/v1/score")!
    struct Dims: Encodable {
        let routing: Int
        let timing: Int
        let context: Int
        let leverage: Int
    }
    struct Payload: Encodable {
        let device_token: String
        let score: Int
        let dims: Dims
        let app_version: String
    }
    typealias Transport = (URLRequest) async throws -> (Data, Int)
    private let defaults: UserDefaults
    private let endpoint: URL
    private let transport: Transport
    private var reporting = false

    init(defaults: UserDefaults = .standard, endpoint: URL = ScoreReporter.endpoint,
         transport: @escaping Transport = ScoreReporter.send) {
        self.defaults = defaults
        self.endpoint = endpoint
        self.transport = transport
    }

    @discardableResult
    func deviceToken() -> String {
        if let token = defaults.string(forKey: "anonDeviceToken"), UUID(uuidString: token) != nil { return token }
        let token = UUID().uuidString
        defaults.set(token, forKey: "anonDeviceToken")
        return token
    }

    func cached(now: Date = Date()) -> AppScoreOut? {
        guard defaults.bool(forKey: "shareAnonymousScore"),
              let date = defaults.object(forKey: "scoreResultAt") as? Date,
              (0...7 * 86400).contains(now.timeIntervalSince(date)),
              let data = defaults.data(forKey: "scoreResult"),
              let result = try? JSONDecoder().decode(AppScoreOut.self, from: data), result.isValid else { return nil }
        return result
    }

    func report(score: Int, dims: Dims, appVersion: String, now: Date = Date()) async -> AppScoreOut? {
        guard defaults.bool(forKey: "shareAnonymousScore") else { return nil }
        guard !(endpoint.host?.contains("REPLACE") ?? true) else { return nil }
        if reporting { return cached(now: now) }
        if let last = defaults.object(forKey: "scoreReportedAt") as? Date,
           last > now || Calendar.current.isDate(last, inSameDayAs: now) { return cached(now: now) }
        guard (0...100).contains(score), [dims.routing, dims.timing, dims.context, dims.leverage]
            .allSatisfy({ (0...100).contains($0) }), appVersion.count <= 20 else { return nil }
        reporting = true
        defer { reporting = false }
        // Count attempts too: an unavailable server never causes repeated daily uploads.
        defaults.set(now, forKey: "scoreReportedAt")
        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpShouldHandleCookies = false
            request.timeoutInterval = 15
            request.httpBody = try JSONEncoder().encode(Payload(device_token: deviceToken(), score: score,
                                                                dims: dims, app_version: appVersion))
            let (data, status) = try await transport(request)
            guard defaults.bool(forKey: "shareAnonymousScore"), status == 200,
                  let result = try? JSONDecoder().decode(AppScoreOut.self, from: data), result.isValid else {
                defaults.removeObject(forKey: "scoreResult")
                defaults.removeObject(forKey: "scoreResultAt")
                return nil
            }
            defaults.set(data, forKey: "scoreResult")
            defaults.set(now, forKey: "scoreResultAt")
            return result
        } catch {
            defaults.removeObject(forKey: "scoreResult")
            defaults.removeObject(forKey: "scoreResultAt")
            return nil
        }
    }

    nonisolated static func send(_ request: URLRequest) async throws -> (Data, Int) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config, delegate: ScoreRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
