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
        let publicCategories: [String: Set<String>] = [
            "routing": ["coding"], "context": ["memory", "research"],
            "leverage": ["automation", "coding", "browser", "data", "design"],
            "timing": ["automation"]]
        let rows = ((snapshot.rankings?.skill ?? []) + (snapshot.rankings?.agent ?? []))
            .filter { $0.installed != true && $0.installationHint != true }
        let preferred = rows.filter {
            publicCategories[key]?.contains($0.category ?? "") == true && (3...5).contains($0.beginner ?? 0)
        }
        let legacy = rows.filter { $0.category == nil && matches.contains($0.taskCategory ?? "") }
        var seen = Set<String>()
        return Array((preferred + legacy).filter { seen.insert($0.url.lowercased()).inserted }.prefix(2))
    }

    static func benefits(_ rows: [Ranking], locale: String) -> [String] {
        var used = Set<String>()
        let categories = [
            "model": ["按任务选择模型", "Choose models for each task"],
            "agent": ["让助手协同完成任务", "Coordinate coding agents"],
            "memory": ["记住项目重点", "Remember project context"],
            "context": ["整理任务上下文", "Organize task context"],
            "skills": ["复用专业技能", "Reuse specialized skills"],
            "automation": ["自动完成重复工作", "Automate repeat work"],
            "productivity": ["专注重要任务", "Focus on important tasks"]]
        return rows.enumerated().map { index, row in
            let category = categories[row.taskCategory ?? ""]?[locale == "zh" ? 0 : 1] ?? ""
            for candidate in [row.tagline, category, row.name] {
                let line = ActionCopy.line(candidate.trimmingCharacters(in: .whitespacesAndNewlines),
                    locale: locale, hanLimit: 12, englishLimit: 29)
                if !line.isEmpty, used.insert(line).inserted { return line }
            }
            var suffix = index + 1
            while true {
                let marker = " · \(suffix)"
                let line = ActionCopy.line(row.name, locale: locale, hanLimit: 12,
                    englishLimit: 29 - marker.count) + marker
                if used.insert(line).inserted { return line }
                suffix += 1
            }
        }
    }

    static func reason(dimension: String, locale: String) -> String {
        let reasons = ["routing": ["让不同模型各展所长", "Choose the right model"],
            "context": ["让 AI 记住重点", "Help AI remember what matters"],
            "leverage": ["把重复工作交给 AI", "Let AI handle repeat tasks"],
            "timing": ["把时间留给更重要的事", "Make time for what matters"]]
        return reasons[dimension]?[locale == "zh" ? 0 : 1] ?? ""
    }
}
