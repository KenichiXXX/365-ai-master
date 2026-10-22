import Foundation

enum DiscoverRanking: String, CaseIterable {
    case skill, agent, learnable, product

    func title(zh: Bool) -> String {
        switch self {
        case .skill: return zh ? "Skill 榜" : "Skills"
        case .agent: return zh ? "Agent 榜" : "Agents"
        case .learnable: return zh ? "技能榜" : "Learn"
        case .product: return zh ? "产品榜" : "Products"
        }
    }
}

enum DiscoverContent {
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
