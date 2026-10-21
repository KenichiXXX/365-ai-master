import Foundation

struct ProFeatures {
    let isPro: Bool
    var growthCurve: Bool { isPro }
    var weeklyReview: Bool { isPro }

    func canLearn(_ card: SkillCard, todayID: String?) -> Bool {
        isPro || card.lit || card.id == todayID
    }

    func rankings(_ rows: [Ranking], expanded: Bool) -> [Ranking] {
        Array(rows.prefix(isPro && expanded ? 20 : 5))
    }
}
