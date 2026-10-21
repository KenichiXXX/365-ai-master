import Foundation
import CoreFoundation

// Refuse redirects so the updater only ever contacts the fixed content endpoint.
private final class ContentRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class ContentUpdater {
    nonisolated static let url = URL(string: "https://raw.githubusercontent.com/19800104zhao-svg/365-ai-master/main/content/daily.json")!
    typealias Loader = () async throws -> (Data, Int)
    private let file: URL
    private let defaults: UserDefaults
    private let loader: Loader
    private var refreshing = false

    init(file: URL = EngineRunner.contentURL, defaults: UserDefaults = .standard,
         loader: @escaping Loader = ContentUpdater.download) {
        self.file = file
        self.defaults = defaults
        self.loader = loader
    }

    nonisolated static func download() async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 15
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config, delegate: ContentRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    @discardableResult
    func refreshIfNeeded(now: Date = Date()) async -> Bool {
        guard !refreshing else { return false }
        if let fetched = defaults.object(forKey: "contentFetchedAt") as? Date,
           Calendar.current.isDate(fetched, inSameDayAs: now) { return false }
        refreshing = true
        defer { refreshing = false }
        do {
            let (data, status) = try await loader()
            guard status == 200, data.count <= 1_000_000,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = object["version"] as? NSNumber,
                  CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1,
                  let skills = object["skills"] as? [[String: Any]], !skills.isEmpty else { return false }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            defaults.set(now, forKey: "contentFetchedAt")
            return true
        } catch { return false }
    }
}
