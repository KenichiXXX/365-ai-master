import SwiftUI

struct CheckupTab: View {
    let snapshot: Snapshot
    @ObservedObject var store: SnapshotStore
    var showUsageFooter = true
    private var zh: Bool { snapshot.locale == "zh" }

    @State private var selectedDimension: String?

    var body: some View {
        Group {
            if let key = selectedDimension,
               let dimension = snapshot.dimensions?.first(where: { $0.key == key }) {
                DimensionDetail(dimension: dimension, growth: snapshot.growth, features: store.features,
                                locale: snapshot.locale ?? store.locale, store: store,
                                back: { selectedDimension = nil })
            } else {
                overview
            }
        }.bauhausTheme()
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: Theme.sectionGap) {
            HStack(alignment: .center, spacing: 16) {
                RecheckScoreView(snapshot: snapshot, store: store)
                VStack(alignment: .leading, spacing: 8) {
                    if let title = CheckupPresentation.title(score: snapshot.overall?.score, locale: snapshot.locale ?? store.locale) {
                        Text(title).font(Theme.title)
                            .help(snapshot.scoreBasisCaption(locale: snapshot.locale ?? store.locale) ?? "")
                    } else {
                        Text(snapshot.overall?.availability == "partial" ? "Partly assessable" : "No assessable records yet", bundle: .module)
                            .font(Theme.body).foregroundStyle(Theme.secondary)
                    }
                    Text(zh ? "你的 AI 掌握度" : "Your AI mastery").font(Theme.label).foregroundStyle(Theme.secondary)
                    if let trend = MePresentation.yesterday(snapshot.progressMe?.vsYesterday, locale: snapshot.locale ?? store.locale) {
                        Text(trend).font(Theme.label)
                            .foregroundStyle((snapshot.progressMe?.vsYesterday ?? 0) > 0 ? Theme.accent : Theme.secondary)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.cardPadding).bauhausPanel()
            GlobalRankCard(store: store, locale: snapshot.locale ?? store.locale)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(zh ? "能力维度" : "Dimensions").font(Theme.sectionTitle)
                    Spacer()
                    Text(zh ? "满分 100" : "Out of 100").font(Theme.label).foregroundStyle(Theme.secondary)
                }
                DimensionBars(dimensions: snapshot.dimensions ?? [], ranking: store.ranking,
                              features: store.features, locale: snapshot.locale ?? store.locale,
                              onSelect: { selectedDimension = $0.key })
                    .padding(Theme.cardPadding).bauhausPanel()
            }
            if let best = snapshot.progressMe?.personalBest {
                HStack(alignment: .firstTextBaseline) {
                    Text(zh ? "个人最佳" : "Personal best").font(Theme.body).foregroundStyle(Theme.secondary)
                    Spacer()
                    if let delta = snapshot.progressMe?.weekDelta {
                        Text(zh ? "本周 \(MePresentation.signed(delta))" : "This week \(MePresentation.signed(delta))")
                            .font(Theme.label).foregroundStyle(Theme.secondary)
                    }
                    Text(String(best)).font(Theme.title).monospacedDigit()
                    Text(zh ? "分" : "pts").font(Theme.label).foregroundStyle(Theme.secondary)
                }
            }
            if store.features.weeklyReview {
                Button(zh ? "本周复盘" : "Weekly review") { store.openWeeklyReview() }
            }
            if showUsageFooter, let usage = snapshot.usageSummary {
                UsageFooter(usage: usage, locale: snapshot.locale ?? store.locale)
            }
        }
    }
}


struct UsageFooter: View {
    let usage: UsageSummary
    let locale: String
    @State private var showUsageDetails = false
    private var zh: Bool { locale == "zh" }

    var body: some View {
        HStack(spacing: 4) {
            Text(usage.caption(locale: locale))
                .font(Theme.label).lineLimit(1).minimumScaleFactor(0.6)
            Button(action: { showUsageDetails.toggle() }) {
                Image(systemName: "info.circle").font(Theme.label)
            }.buttonStyle(.plain).accessibilityLabel(zh ? "使用记录说明" : "Usage details")
                .popover(isPresented: $showUsageDetails) {
                    Text(usage.details(locale: locale))
                        .font(Theme.label).padding(Theme.cardPadding).frame(width: 340).bauhausTheme()
                }
        }.foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

enum CheckupPresentation {
    static func title(score: Int?, locale: String) -> String? {
        guard let score else { return nil }
        switch score {
        case 90...: return locale == "zh" ? "AI 宗师" : "AI Grandmaster"
        case 75...: return locale == "zh" ? "AI 大师" : "AI Master"
        case 60...: return locale == "zh" ? "AI 熟练者" : "AI Practitioner"
        default: return locale == "zh" ? "AI 探索者" : "AI Explorer"
        }
    }

    static func rankCaption(_ ranking: AppScoreOut, locale: String) -> String {
        if ranking.total < 20 {
            return locale == "zh" ? "早期排名 · \(ranking.total) 人中第 \(ranking.rank) 名"
                : "Early ranking · #\(ranking.rank) of \(ranking.total)"
        }
        guard let percentile = ranking.percentile else { return "" }
        return locale == "zh" ? "超过全球 \(percentile)% 的 AI 用户"
            : "Ahead of \(percentile)% of AI users worldwide"
    }

    static func participants(_ ranking: AppScoreOut, locale: String) -> String {
        locale == "zh" ? "\(ranking.total) 人参与 · 第 \(ranking.rank) 名"
            : "\(ranking.total) participants · #\(ranking.rank)"
    }
}

struct GlobalRankCard: View {
    @ObservedObject var store: SnapshotStore
    let locale: String
    @State private var showConsent = false
    private var zh: Bool { locale == "zh" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(zh ? "全球排名" : "Global ranking").font(Theme.sectionTitle).foregroundStyle(Theme.ink)
                    if store.shareAnonymousScore {
                        if let ranking = store.ranking {
                            Text(CheckupPresentation.rankCaption(ranking, locale: locale)).font(Theme.label)
                            if ranking.total >= 20, let change = MePresentation.rankChange(store.rankChange7d, locale: locale) {
                                Text(change).font(Theme.label)
                                    .foregroundStyle((store.rankChange7d ?? 0) > 0 ? Theme.accent : Theme.secondary)
                            }
                            DisclosureGroup {
                                Text(CheckupPresentation.participants(ranking, locale: locale)).font(Theme.label)
                                Text(AppScoreOut.sampleLimitation(locale: locale)).font(Theme.label)
                            } label: {
                                Image(systemName: "info.circle").accessibilityLabel(zh ? "排名说明" : "Ranking details")
                            }
                        } else {
                            Text(store.rankingCaption(locale: locale)).font(Theme.label)
                        }
                    } else {
                        Text(zh ? "尚未加入 · 与全球使用者一起进步" : "Not joined · Grow with AI users worldwide")
                            .font(Theme.label)
                    }
                }.foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
                if !store.shareAnonymousScore {
                    Button(zh ? "加入 ↗" : "Join ↗") { showConsent = true }
                        .buttonStyle(ThemeButtonStyle())
                }
            }
            if showConsent { ScoreConsentPanel(store: store, zh: zh, close: { showConsent = false }) }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.cardPadding).bauhausPanel()
    }
}


struct ScoreConsentPanel: View {
    @ObservedObject var store: SnapshotStore
    let zh: Bool
    let close: () -> Void

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: Theme.grid) {
                Text(ScoreConsent.explanation(locale: zh ? "zh" : "en")).font(Theme.body)
                HStack {
                    Button(zh ? "允许" : "Allow") {
                        Task { await store.allowScoreSharing() }
                        close()
                    }
                    Button(zh ? "暂不" : "Not now", action: close)
                }
            }.padding(Theme.grid * 2).bauhausPanel()
        }.bauhausTheme()
    }
}

enum ScoreConsent {
    static func explanation(locale: String) -> String {
        locale == "zh" ? "开启后，每天最多一次上传：总分和四个维度分，以及一个随机安装编号和 App 版本。不上传任何使用记录、文件或对话。随时可以关闭。"
            : "When on, once a day at most we upload your overall score, your four dimension scores, a random installation ID, and app version. Never your usage logs, files, or conversations. Turn it off anytime."
    }
}

struct RankingSummary: View {
    let caption: String
    let ranking: AppScoreOut?
    let locale: String

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: Theme.grid) {
                Text(caption)
                if let ranking {
                    DisclosureGroup {
                        Text(ranking.participationCaption(locale: locale))
                        Text(AppScoreOut.sampleLimitation(locale: locale))
                    } label: { Image(systemName: "info.circle").accessibilityLabel(locale == "zh" ? "排名说明" : "Ranking details") }
                }
            }.font(Theme.label).foregroundStyle(Theme.secondary)
        }.bauhausTheme()
    }
}

enum MePresentation {
    enum BarAccent { case lowest, highest, neutral }

    static func signed(_ value: Int) -> String {
        value < 0 ? "−\(-value)" : "+\(value)"
    }

    static func yesterday(_ delta: Int?, locale: String) -> String? {
        guard let delta else { return nil }
        if delta == 0 { return locale == "zh" ? "= 与昨天持平" : "= Same as yesterday" }
        let marker = delta > 0 ? "▲" : "▼"
        return locale == "zh" ? "\(marker) 比昨天 \(signed(delta))" : "\(marker) \(signed(delta)) vs yesterday"
    }

    static func rankChange(_ delta: Int?, locale: String) -> String? {
        guard let delta else { return nil }
        let change = delta == 0 ? "=" : "\(delta > 0 ? "▲" : "▼")\(abs(delta))"
        return locale == "zh" ? "本周排名 \(change)" : "Weekly rank \(change)"
    }

    static func barAccent(_ dimension: Dimension, in dimensions: [Dimension]) -> BarAccent {
        let scores = dimensions.compactMap(\.score)
        guard let score = dimension.score, let low = scores.min(), let high = scores.max(), low != high else { return .neutral }
        if score == low { return .lowest }
        if score == high { return .highest }
        return .neutral
    }
}

struct DimensionBars: View {
    let dimensions: [Dimension]
    let ranking: AppScoreOut?
    let features: ProFeatures
    let locale: String
    let onSelect: (Dimension) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(dimensions) { dimension in
                Button { onSelect(dimension) } label: {
                    VStack(alignment: .leading, spacing: Theme.grid) {
                        HStack(spacing: Theme.grid) {
                            Text(dimension.label).font(Theme.body)
                            Spacer(minLength: 0)
                            Text(dimension.score.map(String.init) ?? "—").font(Theme.body).monospacedDigit()
                            if let caption = features.dimensionCaption(ranking, key: dimension.key, locale: locale), dimension.score != nil {
                                Text(caption).font(Theme.label).foregroundStyle(Theme.secondary)
                            }
                        }
                        GeometryReader { proxy in
                            Capsule().fill(Theme.hairline)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Theme.accent)
                                        .frame(width: proxy.size.width * Double(min(100, max(0, dimension.score ?? 0))) / 100)
                                }
                        }.frame(height: Theme.grid)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(dimension.label + (locale == "zh" ? "，查看详情" : ", view details"))
                    .accessibilityValue(dimension.score.map(String.init) ?? "—")
            }
        }
    }

}
