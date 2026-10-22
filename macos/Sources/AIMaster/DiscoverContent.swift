import Foundation

enum DiscoverRanking: String, CaseIterable {
    case skill, agent, learnable, product

    func title(zh: Bool) -> String {
        switch self {
        case .skill: return "Skill"
        case .agent: return "Agent"
        case .learnable: return zh ? "技能" : "Learn"
        case .product: return zh ? "产品" : "Products"
        }
    }
}

enum DiscoverContent {
    static func shortName(_ row: Ranking, in rows: [Ranking]) -> String {
        let name = row.name.split(separator: "/").last.map(String.init) ?? row.name
        let matches = rows.filter {
            ($0.name.split(separator: "/").last.map(String.init) ?? $0.name)
                .caseInsensitiveCompare(name) == .orderedSame
        }
        return matches.count == 1 ? name : row.name
    }

    static func metric(_ row: Ranking, locale: String) -> String {
        if let weekly = row.stars7d {
            let marker = weekly > 0 ? "▲" : weekly < 0 ? "▼" : "="
            return marker + " " + weekly.magnitude.formatted(.number.locale(Locale(identifier: "en_US")))
        }
        return row.growth(locale: locale)
    }

    static func hasLockedRows(count: Int, isPro: Bool) -> Bool { !isPro && count > 10 }

    static let categories: [String: Set<String>] = [
        "routing": ["model", "agent"], "context": ["memory", "context"],
        "leverage": ["skills", "automation"], "timing": ["productivity", "automation"]]

    static func weakest(_ snapshot: Snapshot) -> String? {
        snapshot.dimensions?.filter { $0.score != nil }.min { $0.score! < $1.score! }?.key
    }

    static func picks(_ snapshot: Snapshot) -> [Ranking] {
        guard let key = weakest(snapshot), let matches = categories[key] else { return [] }
        var seen = Set<String>()
        return Array(((snapshot.rankings?.skill ?? []) + (snapshot.rankings?.agent ?? [])).filter {
            $0.installed != true && $0.installationHint != true
                && matches.contains($0.taskCategory ?? "") && seen.insert($0.url.lowercased()).inserted
        }.prefix(2))
    }

    static func reason(dimension: String, locale: String) -> String {
        let reasons = ["routing": ["让不同模型各展所长", "Choose the right model"],
            "context": ["让 AI 记住重点", "Help AI remember what matters"],
            "leverage": ["把重复工作交给 AI", "Let AI handle repeat tasks"],
            "timing": ["把时间留给更重要的事", "Make time for what matters"]]
        return reasons[dimension]?[locale == "zh" ? 0 : 1] ?? ""
    }
}
