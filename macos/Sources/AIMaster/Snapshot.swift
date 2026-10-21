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
