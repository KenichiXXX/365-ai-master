import SwiftUI

struct CheckupTab: View {
    let snapshot: Snapshot
    @ObservedObject var store: SnapshotStore

    @State private var showUsageDetails = false
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
        VStack(alignment: .leading, spacing: Theme.grid) {
            HStack(alignment: .center, spacing: Theme.grid * 2) {
                RecheckScoreView(snapshot: snapshot, store: store)
                VStack(alignment: .leading, spacing: Theme.grid) {
                    ThemeLabel("LEVEL")
                    if let title = CheckupPresentation.title(score: snapshot.overall?.score, locale: snapshot.locale ?? store.locale) {
                        Text(title).font(Theme.title)
                            .help(snapshot.scoreBasisCaption(locale: snapshot.locale ?? store.locale) ?? "")
                    } else {
                        Text(snapshot.overall?.availability == "partial" ? "Partly assessable" : "No assessable records yet", bundle: .module)
                            .font(Theme.body).foregroundStyle(Theme.secondary)
                    }
                    if let trend = MePresentation.yesterday(snapshot.progressMe?.vsYesterday, locale: snapshot.locale ?? store.locale) {
                        HStack(spacing: Theme.grid) {
                            TrendMarker(delta: Double(snapshot.progressMe?.vsYesterday ?? 0))
                            Text(String(trend.dropFirst(2))).font(Theme.body)
                                .foregroundStyle((snapshot.progressMe?.vsYesterday ?? 0) < 0 ? Theme.secondary : Theme.ink)
                        }.accessibilityElement(children: .ignore).accessibilityLabel(trend)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, Theme.grid)
            GlobalRankCard(store: store, locale: snapshot.locale ?? store.locale)
            DimensionBars(dimensions: snapshot.dimensions ?? [], ranking: store.ranking,
                          features: store.features, locale: snapshot.locale ?? store.locale,
                          onSelect: { selectedDimension = $0.key })
            if let personalBest = snapshot.progressMe?.caption(locale: snapshot.locale ?? store.locale) {
                Text(personalBest).font(Theme.body)
            }
            if store.features.weeklyReview {
                Button(zh ? "本周复盘" : "Weekly review") { store.openWeeklyReview() }
            }
            if let usage = snapshot.usageSummary {
                HStack(alignment: .top, spacing: Theme.grid) {
                    Text(usage.caption(locale: snapshot.locale ?? store.locale)
                        .replacingOccurrences(of: " API-equivalent", with: " estimated"))
                        .font(Theme.label).lineLimit(1).minimumScaleFactor(0.6)
                    Button(action: { showUsageDetails.toggle() }) {
                        Image(systemName: "info.circle")
                    }.buttonStyle(.plain).accessibilityLabel(zh ? "使用记录说明" : "Usage details")
                        .popover(isPresented: $showUsageDetails) {
                            Text(usage.details(locale: snapshot.locale ?? store.locale))
                                .font(Theme.label).padding(Theme.grid * 2).frame(width: 340).bauhausTheme()
                        }
                }.foregroundStyle(Theme.secondary)
            }
        }
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
        VStack(alignment: .leading, spacing: Theme.grid) {
            Text("GLOBAL").font(Theme.label).tracking(2)
            if store.shareAnonymousScore {
                if let ranking = store.ranking {
                    Text(CheckupPresentation.rankCaption(ranking, locale: locale)).font(Theme.title)
                    if ranking.total >= 20, let change = MePresentation.rankChange(store.rankChange7d, locale: locale) {
                        Text(change).font(Theme.body).foregroundStyle(Theme.yellow)
                    }
                    DisclosureGroup {
                        Text(CheckupPresentation.participants(ranking, locale: locale)).font(Theme.body)
                        Text(AppScoreOut.sampleLimitation(locale: locale)).font(Theme.label)
                    } label: {
                        Image(systemName: "info.circle").accessibilityLabel(zh ? "排名说明" : "Ranking details")
                    }.tint(Theme.fixedPaper)
                } else {
                    Text(store.rankingCaption(locale: locale)).font(Theme.body)
                }
            } else {
                Text(zh ? "看看你超过了多少 AI 用户" : "See how many AI users you surpass").font(Theme.title)
                Button(zh ? "加入" : "Join") { showConsent = true }
                    .buttonStyle(.plain).font(Theme.body)
                    .padding(Theme.grid)
                    .overlay(Rectangle().strokeBorder(Theme.fixedPaper, lineWidth: Theme.ruleWidth))
                if showConsent { ScoreConsentPanel(store: store, zh: zh, close: { showConsent = false }) }
            }
        }.foregroundStyle(Theme.fixedPaper)
            .frame(maxWidth: .infinity, alignment: .leading).padding(Theme.grid * 2)
            .background(Theme.fixedInk)
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
        VStack(alignment: .leading, spacing: Theme.grid * 2) {
            ForEach(dimensions) { dimension in
                Button { onSelect(dimension) } label: {
                    VStack(alignment: .leading, spacing: Theme.grid) {
                        HStack(spacing: Theme.grid) {
                            Text(dimension.label).font(Theme.body)
                            Text(dimension.score.map(String.init) ?? "—").font(Theme.title).monospacedDigit()
                            Spacer(minLength: 0)
                            if let caption = features.dimensionCaption(ranking, key: dimension.key, locale: locale), dimension.score != nil {
                                Text(caption).font(Theme.label).foregroundStyle(Theme.secondary)
                            }
                        }
                        GeometryReader { proxy in
                            Rectangle().fill(Theme.ink.opacity(0.1))
                                .overlay(alignment: .leading) {
                                    Rectangle().fill(color(dimension))
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

    private func color(_ dimension: Dimension) -> Color {
        switch MePresentation.barAccent(dimension, in: dimensions) {
        case .lowest: return Theme.red
        case .highest: return Theme.blue
        case .neutral: return Theme.ink
        }
    }
}
