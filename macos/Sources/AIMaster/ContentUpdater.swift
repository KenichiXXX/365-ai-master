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
    nonisolated static let url = URL(string: "https://raw.githubusercontent.com/KenichiXXX/365-ai-master/content/daily.json")!
    typealias Loader = () async throws -> (Data, Int)
    private let file: URL
    private let defaults: UserDefaults
    private let loader: Loader
    private var refreshing = false
    private(set) var stale = false

    init(file: URL = EngineRunner.contentURL, defaults: UserDefaults = .standard,
         loader: @escaping Loader = ContentUpdater.download) {
        self.file = file
        self.defaults = defaults
        self.loader = loader
        if let attempted = defaults.object(forKey: "contentAttemptedAt") as? Date {
            stale = (defaults.object(forKey: "contentFetchedAt") as? Date).map { attempted > $0 } ?? true
        }
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
        if let fetched = defaults.object(forKey: "contentAttemptedAt") as? Date,
           (fetched > now || Calendar.current.isDate(fetched, inSameDayAs: now)) { return false }
        defaults.set(now, forKey: "contentAttemptedAt")
        stale = true
        refreshing = true
        defer { refreshing = false }
        do {
            let (data, status) = try await loader()
            guard status == 200, data.count <= 1_000_000,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  PublicContent.validate(object) else { return false }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            defaults.set(now, forKey: "contentFetchedAt")
            stale = false
            return true
        } catch { return false }
    }
}

enum PublicContent {
    static let tools: Set<String> = ["claude_code", "codex", "gemini_cli", "qwen_code", "opencode"]
    static func text(_ value: Any?) -> Bool { (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
    static func bilingual(_ value: Any?) -> Bool {
        guard let value = value as? [String: Any] else { return false }
        return text(value["zh"]) && text(value["en"])
    }
    static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
    static func date(_ value: Any?) -> Bool {
        guard let value = value as? String, matches(value, #"^\d{4}-\d{2}-\d{2}$"#) else { return false }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        return formatter.date(from: value).map { formatter.string(from: $0) == value } ?? false
    }
    static func safeURL(_ value: Any?) -> Bool {
        guard let value = value as? String, !value.contains(where: { $0.isWhitespace }), !value.contains("\\"),
              let c = URLComponents(string: value), c.scheme == "https", let host = c.host?.lowercased(),
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.port == nil, c.path.hasPrefix("/"), host.contains("."), !host.contains(":"),
              !host.hasSuffix(".local"), !host.hasSuffix(".localhost"), !host.hasSuffix(".internal"),
              !host.hasSuffix(".test"), !host.hasSuffix(".invalid"),
              !matches(host, #"\.[0-9]+$"#), matches(host, #"^[a-z0-9-]+(?:\.[a-z0-9-]+)+$"#) else { return false }
        return c.url != nil
    }
    static func spec(_ value: Any?) -> Bool {
        guard let s = value as? [String: Any], let format = s["format"] as? String, matches(format, #"^[a-z][a-z0-9-]{0,79}$"#),
              let versions = s["adapter_versions"] as? [String], !versions.isEmpty else { return false }
        return versions.allSatisfy { matches($0, #"^[0-9]+(?:\.[0-9]+){0,2}$"#) }
    }
    static func compatibility(_ value: Any?) -> Bool {
        guard let c = value as? [String: Any], !c.isEmpty else { return false }
        return c.allSatisfy { tools.contains($0.key) && spec($0.value) }
    }
    static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
    static func validate(_ d: [String: Any]) -> Bool {
        guard number(d["version"]) == 1, date(d["updated_at"]),
              let skills = d["skills"] as? [[String: Any]],
              let reviews = d["review_exercises"] as? [[String: Any]],
              let rankings = d["rankings"] as? [String: Any], let tips = d["tips"] as? [[String: Any]] else { return false }
        let detect = #"^(tool:[A-Za-z][A-Za-z0-9_]*|mcp|skill_any|sidechain|hook|light_model|compaction|self|effort:[a-z][a-z0-9_]*(\|[a-z][a-z0-9_]*)*|instructions:(claude|codex))$"#
        var ids = Set<String>()
        for card in skills + reviews {
            guard let id = card["id"] as? String, text(id), ids.insert(id).inserted,
                  let level = number(card["level"]), level >= 1, level.rounded() == level,
                  let detection = card["detect"] as? String, matches(detection, detect),
                  let validator = card["validator"] as? String, matches(validator, detect),
                  ["title", "why", "prompt", "expected_signal", "limitations"].allSatisfy({ bilingual(card[$0]) }),
                  text(card["review_id"]), compatibility(card["compatibility"]),
                  let steps = card["steps"] as? [String: [String]], ["zh", "en"].allSatisfy({ locale in
                      guard let list = steps[locale], !list.isEmpty else { return false }
                      return list.allSatisfy { text($0) }
                  }) else { return false }
        }
        if let rotate = rankings["rotate"], CFGetTypeID(rotate as CFTypeRef) != CFBooleanGetTypeID() { return false }
        if let origin = rankings["origin"], !(origin is String) || !["bundled", "public"].contains(origin as! String) { return false }
        if rankings["updated_at"] != nil, !date(rankings["updated_at"]) { return false }
        for key in ["source", "updated_at"] where rankings[key] != nil { if !text(rankings[key]) { return false } }
        for kind in ["skill", "agent", "product"] {
            if kind == "product" && rankings[kind] == nil { continue }
            guard let items = rankings[kind] as? [[String: Any]], kind != "product" || items.count >= 5 else { return false }
            for item in items {
                guard text(item["name"]), safeURL(item["url"]), bilingual(item["tagline"]),
                      let names = item["match"] as? [String], names.allSatisfy({ text($0) }) else { return false }
                for key in ["stars", "stars7d"] where item[key] != nil && !(item[key] is NSNull) {
                    guard let n = number(item[key]), n.rounded() == n, abs(n) < 9_007_199_254_740_992 else { return false }
                }
                if let value = item["compatibility"], !(value is NSNull), !compatibility(value) { return false }
                if let value = item["source_url"], !(value is NSNull), !safeURL(value) { return false }
                if let value = item["source_date"], !(value is NSNull), !date(value) { return false }
                if let value = item["source_type"], !(value is String) || !["curated", "repository", "catalog"].contains(value as! String) { return false }
                if let value = item["category"] {
                    guard let category = value as? String,
                          ["coding", "automation", "memory", "browser", "data", "design", "research", "other"].contains(category) else { return false }
                }
                if let value = item["beginner"] {
                    guard let n = number(value), n.rounded() == n, (1...5).contains(n) else { return false }
                }
                if let value = item["task_category"], !(value is NSNull), !text(value) { return false }
                if let value = item["caution"], !bilingual(value) { return false }
            }
        }
        guard tips.allSatisfy({ text($0["id"]) && text($0["source"]) && bilingual($0["title"]) && bilingual($0["detail"]) }) else { return false }
        if let updates = d["tool_updates"] {
            guard let updates = updates as? [[String: Any]], updates.count <= 20 else { return false }
            var seen = Set<String>()
            for u in updates {
                guard let id = u["id"] as? String, text(id), seen.insert(id).inserted,
                      let tool = u["tool"] as? String, ["claude_code", "codex"].contains(tool),
                      safeURL(u["source_url"]), let source = u["source_url"] as? String, official(source, tool: tool),
                      date(u["fetched_at"]), date(u["released_at"]), (u["released_at"] as! String) <= (u["fetched_at"] as! String), spec(u["compatibility"]), bilingual(u["summary"]),
                      let practice = u["practice_id"] as? String, ids.contains(practice) else { return false }
            }
        }
        if let table = d["prices"], !prices(table) { return false }
        return true
    }
    static func official(_ value: String, tool: String) -> Bool {
        guard let c = URLComponents(string: value), let host = c.host else { return false }
        let prefix = tool == "claude_code" ? "/anthropics/claude-code/releases/tag/" : "/openai/codex/releases/tag/"
        return host == "github.com" && c.path.hasPrefix(prefix) && c.path.count > prefix.count
    }

    static func prices(_ value: Any) -> Bool {
        guard let t = value as? [String: Any], text(t["version"]), t["currency"] as? String == "USD",
              t["unit"] as? String == "per_million_tokens", let rows = t["models"] as? [[String: Any]],
              (t["reviewed_at"] == nil || t["reviewed_at"] is NSNull || date(t["reviewed_at"])),
              rows.isEmpty || date(t["reviewed_at"]) else { return false }
        var seen = Set<String>()
        for row in rows {
            guard let model = row["model"] as? String, matches(model, #"^[A-Za-z0-9_.:-]{1,160}$"#),
                  date(row["source_date"]), safeURL(row["source_url"]),
                  let c = row["conditions"] as? [String: String], c.count == 1,
                  let tool = c["tool"], tools.contains(tool), seen.insert(model + ":" + tool).inserted else { return false }
            for key in ["input", "output", "cache_read", "cache_write"] {
                guard let value = row[key] else { return false }
                if !(value is NSNull) { guard let n = number(value), n >= 0 else { return false } }
            }
        }
        return true
    }
}
