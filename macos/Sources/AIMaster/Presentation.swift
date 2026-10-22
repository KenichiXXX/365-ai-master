import Foundation

func tr(_ locale: String, _ zh: String, _ en: String) -> String { locale == "zh" ? zh : en }

enum Rank: Int, CaseIterable {
    case novice, apprentice, practitioner, expert, master

    var floor: Int { [0, 40, 60, 75, 90][rawValue] }
    var next: Rank? { Rank(rawValue: rawValue + 1) }

    static func of(_ score: Int) -> Rank { allCases.last { score >= $0.floor } ?? .novice }

    static func pointsToNext(_ score: Int) -> Int? { of(score).next.map { $0.floor - score } }

    static func progress(_ score: Int) -> Double {
        let rank = of(score)
        guard let next = rank.next else { return 1 }
        return Double(score - rank.floor) / Double(next.floor - rank.floor)
    }

    func title(_ locale: String) -> String {
        let titles = [["新手", "Novice"], ["学徒", "Apprentice"], ["熟练者", "Practitioner"],
                      ["专家", "Expert"], ["大师", "Master"]]
        return titles[rawValue][locale == "zh" ? 0 : 1]
    }

    static func nextCaption(_ score: Int, locale: String) -> String {
        guard let points = pointsToNext(score), let next = of(score).next else {
            return tr(locale, "已是最高段位，保持住", "Top rank. Keep it up")
        }
        return tr(locale, "再提 \(points) 分升到「\(next.title(locale))」", "\(points) points to \(next.title(locale))")
    }
}

enum DimensionState {
    case excellent, good, needsWork

    init(score: Int) { self = score >= 80 ? .excellent : score >= 60 ? .good : .needsWork }

    var tone: Tone {
        switch self {
        case .excellent: return .good
        case .good: return .gold
        case .needsWork: return .low
        }
    }

    func title(_ locale: String) -> String {
        switch self {
        case .excellent: return tr(locale, "优秀", "Great")
        case .good: return tr(locale, "良好", "Good")
        case .needsWork: return tr(locale, "待提升", "Work on it")
        }
    }
}

enum DimensionCopy {
    static func name(_ dimension: Dimension, locale: String) -> String {
        let names = ["routing": ["用对模型", "Model choice"], "timing": ["专注节奏", "Focus rhythm"],
                     "context": ["上下文管理", "Context care"], "leverage": ["能力复用", "Reuse"]]
        return names[dimension.key]?[locale == "zh" ? 0 : 1] ?? dimension.label
    }

    static func blurb(_ key: String, locale: String) -> String {
        let blurbs = [
            "routing": ["难题交给旗舰模型，杂活交给轻量模型，额度花在刀刃上。",
                        "Flagship models for hard problems, light models for chores."],
            "timing": ["把 AI 工作集中在几个时段，少来回切换。", "Batch AI work into a few focused blocks."],
            "context": ["会话短而清楚，长了先压缩，少返工。", "Keep sessions tight and compact them before they bloat."],
            "leverage": ["把常干的活变成技能、命令和规则，配置一次反复用。",
                         "Turn repeat work into skills, commands and rules you reuse."]]
        return blurbs[key]?[locale == "zh" ? 0 : 1] ?? ""
    }
}

enum Pace {
    case comfortable, tight, short

    var tone: Tone {
        switch self {
        case .comfortable: return .good
        case .tight: return .gold
        case .short: return .low
        }
    }

    func title(_ locale: String) -> String {
        switch self {
        case .comfortable: return tr(locale, "够用", "On pace")
        case .tight: return tr(locale, "偏紧", "Tight")
        case .short: return tr(locale, "可能不够", "Running short")
        }
    }

    static func of(usedPct: Double, windowMinutes: Int, resetsAt: Date, now: Date) -> Pace {
        let window = Double(windowMinutes) * 60
        let elapsed = min(1, max(0, 1 - resetsAt.timeIntervalSince(now) / window))
        let used = usedPct / 100
        if used <= elapsed + 0.05 { return .comfortable }
        if used <= elapsed + 0.2 { return .tight }
        return .short
    }
}

enum ISODate {
    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}

struct WeekSummary {
    let valueUSD: Double?
    let valueIsPartial: Bool
    let tokens: Int?
    let quotaLeft: Double?
    let resetsAt: Date?
    let pace: Pace?
    let streakDays: Int?

    init(snapshot: Snapshot, now: Date = Date()) {
        let usage = snapshot.usageSummary
        if let price = usage?.priceEstimate, let coverage = price.coveragePct, coverage > 0 {
            valueUSD = price.matchedSubtotalUsd
            valueIsPartial = coverage < 100
        } else {
            valueUSD = nil
            valueIsPartial = false
        }
        tokens = usage?.tokens7d
        streakDays = snapshot.streak?.days
        let quota = usage?.codexQuota ?? snapshot.quota?.codex
        let windows = [(quota?.primaryPct, quota?.primaryWindowMin, quota?.primaryResetsAt),
                       (quota?.secondaryPct, quota?.secondaryWindowMin, quota?.secondaryResetsAt)]
            .filter { $0.0?.isFinite == true && ($0.1 ?? 0) > 0 }
        guard let quota, let window = windows.first(where: { $0.1 == 10080 }) ?? windows.first,
              let used = window.0, let minutes = window.1,
              quota.freshness(minutes: minutes, reset: window.2, now: now) == "fresh" else {
            quotaLeft = nil
            resetsAt = nil
            pace = nil
            return
        }
        quotaLeft = max(0, min(100, 100 - used))
        resetsAt = ISODate.parse(window.2)
        pace = resetsAt.map { Pace.of(usedPct: used, windowMinutes: minutes, resetsAt: $0, now: now) }
    }

    static func money(_ value: Double) -> String {
        "$" + value.formatted(.number.locale(Locale(identifier: "en_US")).precision(.fractionLength(0)))
    }

    static func resetCaption(_ date: Date, now: Date, locale: String) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds < 86400 {
            let hours = max(1, Int(seconds / 3600))
            return tr(locale, "\(hours) 小时后重置", "Resets in \(hours)h")
        }
        let days = Int(seconds / 86400)
        return tr(locale, "\(days) 天后重置", "Resets in \(days)d")
    }
}

enum TodayStatus: Equatable {
    case ready, waiting, done

    static func of(_ card: SkillCard, feedback: String?) -> TodayStatus {
        if card.lit { return .done }
        if feedback == "started" || feedback == "copied" || card.evidenceKind == "started" { return .waiting }
        return .ready
    }
}

extension SkillCard {
    var autoDetects: Bool { (detect ?? "self") != "self" }
}

struct PathLevel: Identifiable {
    let level: Int
    let title: String
    let cards: [SkillCard]
    var id: Int { level }
    var lit: Int { cards.filter(\.lit).count }

    static func levels(_ book: SkillBook, locale: String) -> [PathLevel] {
        let fallback = [1: ["入门", "Basics"], 2: ["进阶", "Intermediate"], 3: ["高手", "Advanced"]]
        return Set(book.cards.map(\.level)).sorted().map { level in
            let title = book.groups?.first { $0.level == level }?.title ?? fallback[level]?[locale == "zh" ? 0 : 1] ?? "\(level)"
            return PathLevel(level: level, title: title, cards: book.cards.filter { $0.level == level })
        }
    }
}

enum ScoreConsent {
    static func explanation(locale: String) -> String {
        tr(locale, "开启后，每天最多上传一次：总分、四项分数、一个随机安装编号和 App 版本。不上传任何使用记录、文件或对话，随时可以关闭。",
           "When on, at most once a day we upload your overall score, four dimension scores, a random installation ID and the app version. Never your usage logs, files or conversations. Turn it off anytime.")
    }
}

enum MePresentation {
    static func signed(_ value: Int) -> String { value < 0 ? "−\(-value)" : "+\(value)" }
}
