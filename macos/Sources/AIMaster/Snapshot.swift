import Foundation

struct Snapshot: Decodable {
    let coverage: [String: SourceCoverage]?
    let schema: Int
    let generatedAt: String?
    let locale: String?
    let tools: [ToolUsage]?
    let quota: Quota?
    let dimensions: [Dimension]?
    let overall: Overall?
    let village: Village?
    let todayTip: Tip?
    let notices: [String]?
    let error: String?
    let labels: SnapshotLabels?
    let book: SkillBook?
    let rankings: Rankings?
    let dailyTip: DailyTip?
    let streak: Streak?
    let badges: [Badge]?
    let usageSummary: UsageSummary?
    let growth: Growth?
    let weekly: WeeklyReview?
}

struct ToolUsage: Decodable, Identifiable {
    var id: String { tool }
    let tool: String
    let tier: String
    let detected: Bool
    let error: String?
    let usageToday: Usage?
    let usage7d: Usage?
    let byModel: [ModelUsage]?
    enum CodingKeys: String, CodingKey {
        case tool, tier, detected, error, usageToday, byModel
        case usage7d = "usage7D"
    }
}

struct Usage: Decodable {
    let tokens: Int
    let costUsd: Double
}

struct ModelUsage: Decodable, Identifiable {
    var id: String { model }
    let model: String
    let tokens: Int
    let costUsd: Double
}

struct Quota: Decodable {
    let codex: CodexQuota?
}

struct CodexQuota: Decodable {
    let primaryPct: Double?
    let primaryWindowMin: Int?
    let primaryResetsAt: String?
    let secondaryPct: Double?
    let secondaryWindowMin: Int?
    let secondaryResetsAt: String?
    let planType: String?
}

struct Dimension: Decodable, Identifiable {
    var id: String { key }
    let key: String
    let label: String
    let score: Int
}

struct Overall: Decodable {
    let score: Int
    let tier: String
}

struct Village: Decodable {
    let current: String?
    let rankTitle: String
    let quests: [Quest]
}

struct Quest: Decodable, Identifiable {
    var id: String { key }
    let key: String
    let title: String
    let status: String
    let passedAt: String?
    let progressHint: String?
}

struct Tip: Decodable {
    let title: String
    let why: String
    let steps: [String]
    let promptForClaude: String
    let source: TipSource
}

struct TipSource: Decodable {
    let kind: String
    let ref: String
}

struct SnapshotLabels: Decodable {
    let noTools: String
    let toolUnavailable: String
}

struct SkillBook: Decodable {
    let lit: Int
    let total: Int
    let cards: [SkillCard]
    let today: SkillCard?
    var groups: [SkillGroup]? = nil
    var nextBadge: NextBadge? = nil
}

struct SkillGroup: Decodable, Identifiable {
    var id: Int { level }
    let level: Int
    let title: String
    let lit: Int
    let total: Int
    let missing: [String]
}

struct NextBadge: Decodable {
    let id: String
    let title: String
    let have: Int
    let need: Int
}

struct SkillCard: Decodable, Identifiable {
    let id: String
    let title: String
    let why: String
    let prompt: String
    let level: Int
    let lit: Bool
    let how: String?
    var detect: String? = nil

    var isSelfReport: Bool { detect == "self" || how == "self" }
}

struct Rankings: Decodable {
    let skill: [Ranking]?
    let agent: [Ranking]?
    let source: String?
}

struct Ranking: Decodable {
    let name: String
    let url: String
    let tagline: String
    let installed: Bool
    var stars: Int? = nil
    var stars7d: Int? = nil

    func growth(locale: String) -> String {
        guard let stars else { return "" }
        let zh = locale == "zh"
        var count = UsageSummary.tokens(stars, locale: locale)
        if zh, stars >= 10_000 {
            let divisor = stars >= 100_000_000 ? 1e8 : 1e4
            count = (Double(stars) / divisor).formatted(.number.locale(Locale(identifier: "en_US"))
                .grouping(.never).precision(.fractionLength(0...1))) + (stars >= 100_000_000 ? "亿" : "万")
        }
        var text = "★ " + count
        if let stars7d {
            let delta = stars7d.formatted(.number.locale(Locale(identifier: "en_US")))
            let signed = stars7d >= 0 ? "+" + delta : delta
            text += zh ? " · 本周 \(signed)" : " · \(signed) this week"
        }
        return text
    }
}

struct DailyTip: Decodable {
    let title: String
    let detail: String
    let source: String?
}

struct Streak: Decodable { let days: Int }

struct Badge: Decodable, Identifiable {
    let id: String
    let title: String
    let earned: Bool
}

struct UsageSummary: Decodable {
    let tokens7d: Int
    let costUsd7d: Double
    let codexQuotaPct: Double?

    enum CodingKeys: String, CodingKey {
        case tokens7d = "tokens7D", costUsd7d = "costUsd7D", codexQuotaPct
    }

    static func tokens(_ count: Int, locale: String) -> String {
        if locale == "zh", count >= 10_000 {
            let billions = count >= 100_000_000
            let value = Double(count) / (billions ? 1e8 : 1e4)
            let text = value.formatted(.number.locale(Locale(identifier: "en_US"))
                .precision(.fractionLength(billions ? 1 : 0)))
            return text + (billions ? " 亿" : " 万")
        }
        let units: [(Double, String)] = locale == "zh" ? [] : [(1e9, "B"), (1e6, "M"), (1e3, "K")]
        for (divisor, suffix) in units where Double(count) >= divisor {
            let value = (Double(count) / divisor * 10).rounded() / 10
            let text = value.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))
                .grouping(.never).precision(.fractionLength(0...1)))
            return text + suffix
        }
        return String(count)
    }

    func caption(locale: String) -> String {
        let zh = locale == "zh"
        let cost = String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), costUsd7d)
        var text = zh ? "本周 \(Self.tokens(tokens7d, locale: locale)) tokens · 折算 $\(cost)"
            : "This week \(Self.tokens(tokens7d, locale: locale)) tokens · ≈$\(cost) API-equivalent"
        if let quota = codexQuotaPct {
            let pct = String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), quota)
            text += zh ? " · Codex 周额度 \(pct)%" : " · Codex weekly \(pct)%"
        }
        return text
    }
}

struct Growth: Decodable {
    let days: [ScoreDay]
    let weekDelta: Int?
}

struct ScoreDay: Decodable, Identifiable {
    var id: String { date }
    let date: String
    let score: Int
}

struct WeeklyReview: Decodable {
    let weekStart: String
    let scoreDelta: Int?
    let cardsLitThisWeek: [String]
    let questsPassedThisWeek: [String]
    let daysActive: Int

    func summary(locale: String) -> String {
        let change = scoreDelta.map { $0 >= 0 ? "+\($0)" : String($0) }
        if locale == "zh" {
            return "活跃 \(daysActive) 天 · 新点亮 \(cardsLitThisWeek.count) 张 · " + (change.map { "分数 \($0)" } ?? "暂无上周数据")
        }
        return "\(daysActive) active days · \(cardsLitThisWeek.count) new skills · " + (change.map { "Score \($0)" } ?? "No data last week")
    }
}

// Schema 1/2 omit coverage; their legacy observations remain decodable.
struct SourceCoverage: Decodable {
    enum Status: String, Decodable {
        case notDetected = "not_detected"
        case noLogs = "no_logs"
        case permissionDenied = "permission_denied"
        case unsupported, partial, ok
    }
    enum Availability: String, Decodable { case available, unknown, unsupported }
    let adapterVersion: String
    let format: String
    let status: Status
    let startUtc: String?
    let endUtc: String?
    let validUsageCount: Int
    let malformedCount: Int
    let skippedCount: Int
    let signals: [String: Availability]
}
