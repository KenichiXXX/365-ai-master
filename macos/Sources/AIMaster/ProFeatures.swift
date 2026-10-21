import Foundation

struct ProFeatures {
    let isPro: Bool
    init(isPro: Bool) { self.isPro = isPro }
    init(entitlement: ProEntitlement) { isPro = entitlement.isPro }
    var growthCurve: Bool { isPro }
    var weeklyReview: Bool { isPro }

    func dimensionCaption(_ ranking: AppScoreOut?, key: String, locale: String) -> String? {
        guard isPro, let ranking, ranking.isValid, let dimension = ranking.dims?[key] else { return nil }
        if ranking.small_sample {
            return locale == "zh" ? "第 \(dimension.rank) 名" : "#\(dimension.rank)"
        }
        guard let percentile = dimension.percentile else { return nil }
        return locale == "zh" ? "击败 \(percentile)%" : "Beat \(percentile)%"
    }

    func canLearn(_ card: SkillCard, todayID: String?) -> Bool {
        isPro || card.lit || card.id == todayID
    }

    func rankings(_ rows: [Ranking], expanded: Bool) -> [Ranking] {
        Array(rows.prefix(isPro && expanded ? 20 : 5))
    }
}
