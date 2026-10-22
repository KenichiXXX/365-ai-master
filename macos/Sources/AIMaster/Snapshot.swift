import Foundation

struct Snapshot: Decodable {
    let localValidation: LocalValidation?
    let coverage: [String: SourceCoverage]?
    let firstPractice: FirstPractice?
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
    let toolUpdates: [PublicToolUpdate]?
    let streak: Streak?
    let badges: [Badge]?
    let usageSummary: UsageSummary?
    let growth: Growth?
    let weekly: WeeklyReview?

    var relevantToolUpdates: [PublicToolUpdate] {
        (toolUpdates ?? []).filter { update in
            guard let coverage = coverage?[update.tool],
                  coverage.status != .unsupported, coverage.status != .notDetected,
                  tools?.contains(where: { $0.tool == update.tool && $0.detected }) == true,
                  let compatibility = update.compatibility else { return false }
            return compatibility.format == coverage.format && compatibility.adapterVersions.contains(coverage.adapterVersion)
        }
    }

    func scoreBasisCaption(locale: String) -> String? {
        guard overall?.score != nil, let dimensions else { return nil }
        let count = dimensions.filter { $0.score != nil }.count
        return locale == "zh" ? "基于 \(count)/4 项" : "Based on \(count) of 4"
    }

    var hasEvaluableScores: Bool {
        guard let score = overall?.score, (0...100).contains(score),
              let dimensions, dimensions.count == 4,
              Set(dimensions.map(\.key)) == Set(["routing", "timing", "context", "leverage"]) else { return false }
        return (overall?.availability == nil || overall?.availability == "available") && dimensions.allSatisfy {
            ($0.availability == nil || $0.availability == "available") && $0.score.map { (0...100).contains($0) } == true
        }
    }
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
    let costUsd: Double?
}

struct ModelUsage: Decodable, Identifiable {
    var id: String { model }
    let model: String
    let tokens: Int
    let costUsd: Double?
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
    let recordedAt: String?
    let freshness: String?

    func freshness(minutes: Int, reset: String?, now: Date = Date()) -> String {
        let iso = ISO8601DateFormatter()
        func parse(_ value: String) -> Date? {
            if let date = iso.date(from: value) { return date }
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let date = iso.date(from: value)
            iso.formatOptions = [.withInternetDateTime]
            return date
        }
        guard let recordedAt, let recorded = parse(recordedAt) else { return "unknown" }
        let age = now.timeIntervalSince(recorded)
        if age < 0 { return "future" }
        if age > Double(minutes) * 60 { return "stale" }
        if let reset, let date = parse(reset), date <= now { return "stale" }
        return "fresh"
    }
}

struct Dimension: Decodable, Identifiable {
    var id: String { key }
    let key: String
    let label: String
    let score: Int?
    var availability: String? = nil
    var evidence: [RuleEvidence]? = nil
    var verdict: String? = nil
    var deductions: [ScoreDeduction]? = nil
    var steps: [String]? = nil
    var prompt: String? = nil
}

struct ScoreDeduction: Decodable {
    let title: String
    let points: Int
}

struct RuleEvidence: Decodable {
    var ruleId: String? = nil
    var version: String? = nil
    var windowDays: Int? = nil
    var numerator: Double? = nil
    var denominator: Double? = nil
    var availability: String? = nil
    var explanation: String? = nil
    var limitation: String? = nil
    var label: String? = nil
    var value: String? = nil
    var target: String? = nil
}

struct Overall: Decodable {
    let score: Int?
    let tier: String?
    var availability: String? = nil
    var scoreVersion: String? = nil
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
    var evidenceKind: String? = nil
    var evidenceLabel: String? = nil
}

struct Tip: Decodable {
    let title: String
    let why: String
    let steps: [String]
    let promptForClaude: String
    let source: TipSource
    var actionId: String? = nil
    var ruleId: String? = nil
    var evidenceSummary: String? = nil
    var limitation: String? = nil
    var validationKind: String? = nil
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
    var yesterday: [TrackedPractice]? = nil
    var configurationCount: Int? = nil
    var selfReportCount: Int? = nil
    var practiceCalendar: PracticeCalendarData? = nil
}

struct TrackedPractice: Decodable, Identifiable {
    var id: String { attemptId }
    let attemptId: String
    let skillId: String
    let status: String
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

    var evidenceKind: String? = nil
    var evidenceLabel: String? = nil
    var validator: String? = nil
    var automaticSupported: Bool? = nil
    var mode: String? = nil
    var contentRevision: String? = nil
    var steps: [String]? = nil
    var expectedSignal: String? = nil
    var limitations: String? = nil

    var isSelfReport: Bool { automaticSupported == false || validator == "self" || detect == "self" || how == "self" }

    func evidenceText(locale: String) -> String {
        if let evidenceLabel { return evidenceLabel }
        let labels = [
            "ready": ["待实践", "Ready to practise"],
            "started": ["已开始，等待新记录", "Started; waiting for new records"],
            "log_observed": ["日志已观察", "Observed in logs"],
            "reuse": ["再次使用", "Used again"],
            "historical": ["历史记录", "Historical record"],
            "configuration": ["配置存在", "Configuration found"],
            "self_reported": ["已尝试（自报）", "Tried (self-reported)"]]
        let kind = evidenceKind ?? (lit ? "historical" : "ready")
        return (labels[kind] ?? labels["ready"]!)[locale == "zh" ? 0 : 1]
    }
}

struct Rankings: Decodable {
    let skill: [Ranking]?
    let agent: [Ranking]?
    let source: String?
    let origin: String?
    let updatedAt: String?

    func footnote(locale: String) -> String {
        if origin != "cached" { return locale == "zh" ? "内置精选" : "Bundled selection" }
        return locale == "zh" ? "数据：The Skill Leaderboard · GitHub · 安装前请自行核对权限"
            : "Data: The Skill Leaderboard · GitHub · Check permissions before installing"
    }

    func sourceLabel(locale: String, stale: Bool = false) -> String {
        if origin != "cached" { return locale == "zh" ? "内置精选，非实时榜单" : "Bundled selection, not a live leaderboard" }
        let date = updatedAt.map { DisplayDate.short($0, locale: locale) } ?? "—"
        let label = locale == "zh" ? "缓存内容，更新于 \(date)" : "Cached content, updated \(date)"
        return stale ? label + (locale == "zh" ? "（更新失败，保留缓存）" : " (update failed; cache retained)") : label
    }
}

struct Ranking: Decodable {
    let name: String
    let url: String
    let tagline: String
    var installed: Bool? = nil
    var stars: Int? = nil
    var stars7d: Int? = nil
    var sourceUrl: String? = nil
    var sourceDate: String? = nil
    var sourceType: String? = nil
    var taskCategory: String? = nil
    var compatibility: [String: PublicCompatibility]? = nil
    var caution: String? = nil
    var installationHint: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case name, url, tagline, installed, stars, stars7d, sourceUrl, sourceDate, sourceType, taskCategory, compatibility, caution, installationHint
    }

    func compatibilityLabel(locale: String) -> String {
        guard let compatibility, !compatibility.isEmpty else { return locale == "zh" ? "兼容性未知" : "Compatibility unknown" }
        return compatibility.keys.sorted().map { tool in
            let spec = compatibility[tool]!
            return "\(tool): \(spec.format) (\(spec.adapterVersions.joined(separator: ", ")))"
        }.joined(separator: " · ")
    }

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

struct Streak: Decodable { let days: Int; var label: String? = nil }

struct Badge: Decodable, Identifiable {
    let id: String
    let title: String
    let earned: Bool
}

struct UsageSummary: Decodable {
    let tokens7d: Int
    let costUsd7d: Double?
    let codexQuotaPct: Double? // Legacy only: percentage alone proves no window.
    var priceEstimate: PriceEstimate? = nil
    var codexQuota: CodexQuota? = nil
    var labels: [String: String]? = nil

    enum CodingKeys: String, CodingKey {
        case tokens7d = "tokens7D", costUsd7d = "costUsd7D", codexQuotaPct, priceEstimate, codexQuota, labels
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
        var text = (zh ? "本周 " : "This week ") + Self.tokens(tokens7d, locale: locale) + " tokens"
        if let price = priceEstimate, let coverage = price.coveragePct, coverage > 0 {
            let amount = price.matchedSubtotalUsd.formatted(.number.locale(Locale(identifier: "en_US"))
                .grouping(.never).precision(.fractionLength(0...2)))
            // Partial matches must never look like the full week's cost.
            text += zh ? " · \(coverage < 100 ? "部分" : "")折算 $\(amount)"
                : " · ≈$\(amount) API-equivalent\(coverage < 100 ? " (partial)" : "")"
        } else { text += zh ? " · 价格未知" : " · Price unknown" }
        if let quota = codexQuota {
            let windows = [(quota.primaryPct, quota.primaryWindowMin, quota.primaryResetsAt),
                           (quota.secondaryPct, quota.secondaryWindowMin, quota.secondaryResetsAt)]
            // Prefer the weekly window, otherwise show the actual recorded duration.
            let valid = windows.filter { $0.0?.isFinite == true && ($0.1 ?? 0) > 0 }
            if let window = valid.first(where: { $0.1 == 10080 }) ?? valid.first,
               let pct = window.0, let minutes = window.1 {
                let duration = minutes == 10080 ? (zh ? "周额度" : "weekly")
                    : minutes % 60 == 0 ? (zh ? "\(minutes / 60)小时额度" : "\(minutes / 60)-hour")
                    : (zh ? "\(minutes)分钟额度" : "\(minutes)-minute")
                let percent = pct.formatted(.number.locale(Locale(identifier: "en_US")).precision(.fractionLength(0...1)))
                text += " · Codex \(duration) \(percent)%"
                if let reset = window.2 {
                    let date = DisplayDate.short(reset, locale: locale, time: false)
                    text += zh ? "（\(date)重置）" : " (resets \(date))"
                }
                let freshness = quota.freshness(minutes: minutes, reset: window.2)
                if freshness == "stale" { text += zh ? "（过时）" : " (stale)" }
                if freshness == "future" { text += zh ? "（时间异常）" : " (future-dated)" }
            }
        }
        return text
    }

    func details(locale: String) -> String {
        let zh = locale == "zh"
        func copy(_ key: String, _ en: String, _ chinese: String) -> String {
            labels?[key] ?? (zh ? chinese : en)
        }
        func fill(_ template: String, _ pairs: [String: String]) -> String {
            pairs.reduce(template) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
        }
        func number(_ value: Double) -> String {
            String(format: "%.4g", locale: Locale(identifier: "en_US_POSIX"), value)
        }
        var text = copy("tokens", "Logged tokens (excluding cache reads)", "日志 Token（不含缓存读取）")
            + ": " + Self.tokens(tokens7d, locale: locale)
        if let price = priceEstimate, let pct = price.coveragePct, pct > 0 {
            text += " · " + fill(copy("matched_subtotal", "Matched subtotal USD {amount}, price coverage {pct}%",
                                     "已匹配部分折算 USD {amount}，价格覆盖 {pct}%"),
                                ["amount": number(price.matchedSubtotalUsd), "pct": number(pct)])
        } else {
            text += " · " + copy("price_unknown", "Price unknown", "价格未知")
        }
        if let price = priceEstimate, let coverage = price.coveragePct, coverage > 0, coverage < 100 {
            text += " · " + copy("price_partial_unknown", "Some model prices are unknown", "部分模型价格未知")
        }
        if (priceEstimate?.tierEstimatedTokens ?? 0) > 0 {
            text += " · " + copy("price_tier_basis",
                "Known model tiers use approximate API rates; cache writes use the input tier rate",
                "已知模型按档位近似折算，缓存写入按输入档位价估算")
        }
        text += " · " + copy("price_basis", "API-equivalent at public prices, not a subscription bill", "按公开 API 单价折算，非订阅账单")
        if let date = priceEstimate?.reviewedAt {
            text += " · " + fill(copy("price_date", "Price table dated {date}", "价格表日期 {date}"), ["date": DisplayDate.short(date, locale: locale)])
        }
        if let quota = codexQuota {
            for (pct, minutes, reset) in [(quota.primaryPct, quota.primaryWindowMin, quota.primaryResetsAt),
                                           (quota.secondaryPct, quota.secondaryWindowMin, quota.secondaryResetsAt)] {
                guard let pct, pct.isFinite, let minutes, minutes > 0 else { continue }
                let template = minutes == 10080
                    ? copy("quota_week", "Codex weekly window: {pct}% used", "Codex 周窗口已用 {pct}%")
                    : minutes % 60 == 0
                    ? copy("quota_hours", "Codex {hours}-hour window: {pct}% used", "Codex {hours} 小时窗口已用 {pct}%")
                    : copy("quota_minutes", "Codex {minutes}-minute window: {pct}% used", "Codex {minutes} 分钟窗口已用 {pct}%")
                text += " · " + fill(template, ["pct": number(pct), "hours": number(Double(minutes) / 60), "minutes": String(minutes)])
                if let reset {
                    text += " · " + fill(copy("quota_reset", "Resets {date}", "重置时间 {date}"), ["date": DisplayDate.short(reset, locale: locale)])
                }
            }
            if let date = quota.recordedAt {
                text += " · " + fill(copy("quota_recorded", "Quota recorded {date}", "额度记录时间 {date}"), ["date": DisplayDate.short(date, locale: locale)])
            }
            let minutes = [quota.primaryWindowMin, quota.secondaryWindowMin].compactMap { $0 }.filter { $0 > 0 }
            let preferred = minutes.first(where: { $0 == 10080 }) ?? minutes.first
            let reset = preferred == quota.primaryWindowMin ? quota.primaryResetsAt : quota.secondaryResetsAt
            let freshness = preferred.map { quota.freshness(minutes: $0, reset: reset) } ?? "unknown"
            if freshness == "stale" {
                text += " · " + copy("quota_stale", "Quota record is stale", "额度记录已过时")
            } else if freshness == "future" {
                text += " · " + copy("quota_future", "Quota record is future-dated", "额度记录时间在未来")
            }
        }
        return text
    }
}

struct PriceEstimate: Decodable {
    let matchedSubtotalUsd: Double
    let coveragePct: Double?
    let reviewedAt: String?
    var tierEstimatedTokens: Int? = nil
}

struct HistoryComparison: Decodable {
    let reason: String?
    let window: String?
}

struct Growth: Decodable {
    let days: [ScoreDay]
    let weekDelta: Double?
    let comparison: HistoryComparison?
    let labels: [String: String]?

    // Explicit series IDs prevent Charts from bridging unknown dates or versions.
    var segments: [[ScoreDay]] {
        var result: [[ScoreDay]] = []
        var previous: ScoreDay?
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        for day in days {
            guard let score = day.score, (0...100).contains(score),
                  let date = formatter.date(from: day.date) else { previous = nil; continue }
            guard let version = day.scoreVersion, version != "legacy_unknown_version" else {
                result.append([day]); previous = nil; continue
            }
            let consecutive = previous.flatMap { formatter.date(from: $0.date) }
                .map { date.timeIntervalSince($0) == 86400 } ?? false
            if consecutive, previous?.scoreVersion == version, previous?.ruleVersion == day.ruleVersion {
                result[result.count - 1].append(day)
            } else { result.append([day]) }
            previous = day
        }
        return result
    }

    func forDimension(_ key: String) -> Growth {
        Growth(days: days.map { day in
            ScoreDay(date: day.date, score: day.dims?[key] ?? nil,
                     scoreVersion: day.scoreVersion, ruleVersion: day.ruleVersion)
        }, weekDelta: nil, comparison: nil, labels: labels)
    }

    var comparableDelta: Double? {
        comparison?.reason == nil && comparison?.window == "matched_completed_weekdays" ? weekDelta : nil
    }
}

struct ScoreDay: Decodable, Identifiable {
    var id: String { date }
    let date: String
    let score: Int?
    let scoreVersion: String?
    let ruleVersion: String?
    var dims: [String: Int?]? = nil
}

struct ReviewStatement: Decodable {
    let text: String
    let metricId: String?
    let evidenceIds: [String]?
    let practiceId: String?
    let reason: String?
}

struct WeeklyReview: Decodable {
    let weekStart: String
    let scoreDelta: Double?
    let cardsLitThisWeek: [String]
    let questsPassedThisWeek: [String]
    let daysActive: Int
    let comparison: HistoryComparison?
    let observedChange: ReviewStatement?
    let uncertainty: ReviewStatement?
    let nextPractice: ReviewStatement?
    let reportText: String?
    let selfReportIds: [String]?
    let configurationIds: [String]?
    let reuseEvidenceIds: [String]?

    func summary(locale: String) -> String {
        guard comparison?.window == "matched_completed_weekdays", comparison?.reason == nil, let delta = scoreDelta else {
            return locale == "zh" ? "可比数据积累中" : "Collecting comparable data"
        }
        let signed = String(format: "%+.2f", locale: Locale(identifier: "en_US_POSIX"), delta)
        return locale == "zh" ? "同星期窗口均分变化 \(signed) 分"
            : "Mean score change for matched weekdays: \(signed) points"
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
    enum Availability: String, Decodable { case observed, supported, available, unknown, unsupported }
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

struct FirstPractice: Decodable {
    let title: String
    let prompt: String
    let noProjectPrompt: String
    let limitation: String
    let validationKind: String
}

struct PublicCompatibility: Decodable {
    let format: String
    let adapterVersions: [String]
}

struct PublicToolUpdate: Decodable, Identifiable {
    let id: String
    let tool: String
    let sourceUrl: String
    let fetchedAt: String
    let releasedAt: String
    let summary: String
    let practiceId: String
    let compatibility: PublicCompatibility?
}
