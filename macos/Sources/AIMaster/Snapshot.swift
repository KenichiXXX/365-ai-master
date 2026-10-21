import Foundation

struct Snapshot: Decodable {
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
}

struct SkillCard: Decodable, Identifiable {
    let id: String
    let title: String
    let why: String
    let prompt: String
    let level: Int
    let lit: Bool
    let how: String?
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
