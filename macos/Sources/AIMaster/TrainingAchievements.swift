import Foundation

/// Numeric progress and stable IDs only; missing categories do not erase prior observations.
struct TrainingAchievementProgress: Equatable {
    let level: Int?
    let badges: [String: String]?
    let quests: [String: String]?
    let bestScore: Int?
    let scoreVersion: String

    init(snapshot: Snapshot) {
        level = snapshot.trainingGame?.level
        if snapshot.badges != nil || snapshot.trainingGame != nil {
            var titles: [String: String] = [:]
            for badge in snapshot.badges ?? [] where badge.earned { titles[badge.id] = badge.title }
            for badge in snapshot.trainingGame?.weeklyBadges ?? [] {
                titles[badge] = badge.replacingOccurrences(of: "weekly:", with: "")
            }
            badges = titles
        } else { badges = nil }
        if let village = snapshot.village {
            quests = Dictionary(village.quests.filter { $0.status == "passed" }.map { ($0.key, $0.title) },
                                uniquingKeysWith: { first, _ in first })
        } else { quests = nil }
        let version = snapshot.overall?.scoreVersion ?? "legacy"
        scoreVersion = version
        if let score = snapshot.overall?.score, (0...100).contains(score),
           snapshot.overall?.availability != "unavailable" {
            let history = (snapshot.growth?.days ?? []).filter {
                ($0.scoreVersion ?? "legacy") == version
            }.compactMap(\.score).filter { (0...100).contains($0) }
            bestScore = max(score, history.max() ?? score)
        } else { bestScore = nil }
    }
}

struct TrainingMoment: Identifiable {
    let id: String
    let zh: String
    let en: String
    func title(zh: Bool) -> String { zh ? self.zh : en }
}

struct TrainingAchievementLedger: Codable {
    private var level: Int?
    private var badgeIDs: Set<String>?
    private var questIDs: Set<String>?
    private var bestByVersion: [String: Int] = [:]

    mutating func observe(_ progress: TrainingAchievementProgress) -> [TrainingMoment] {
        var result: [TrainingMoment] = []
        if let current = progress.level {
            if let previous = level, current > previous {
                result.append(TrainingMoment(id: "level:\(current)", zh: "升到 Lv.\(current)", en: "Reached Lv.\(current)"))
            }
            level = max(level ?? current, current)
        }
        if let badges = progress.badges {
            if let seen = badgeIDs {
                for id in Set(badges.keys).subtracting(seen).sorted() {
                    result.append(TrainingMoment(id: "badge:\(id)", zh: "获得徽章 · \(badges[id]!)", en: "Badge earned · \(badges[id]!)"))
                }
            }
            badgeIDs = (badgeIDs ?? []).union(badges.keys)
        }
        if let quests = progress.quests {
            if let seen = questIDs {
                for id in Set(quests.keys).subtracting(seen).sorted() {
                    result.append(TrainingMoment(id: "quest:\(id)", zh: "闯关成功 · \(quests[id]!)", en: "Quest passed · \(quests[id]!)"))
                }
            }
            questIDs = (questIDs ?? []).union(quests.keys)
        }
        if let score = progress.bestScore {
            if let previous = bestByVersion[progress.scoreVersion], score > previous {
                result.append(TrainingMoment(id: "best:\(progress.scoreVersion):\(score)",
                    zh: "新纪录！个人最佳 \(score)", en: "New record! Personal best \(score)"))
            }
            bestByVersion[progress.scoreVersion] = max(bestByVersion[progress.scoreVersion] ?? score, score)
        }
        return result
    }
}
