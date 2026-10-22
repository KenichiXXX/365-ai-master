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
            VStack(alignment: .leading, spacing: Theme.grid) {
                ThemeLabel("LEVEL")
                RecheckScoreView(snapshot: snapshot, store: store)
                if let title = CheckupPresentation.title(score: snapshot.overall?.score, locale: snapshot.locale ?? store.locale) {
                    Text(title).font(Theme.title)
                        .help(snapshot.scoreBasisCaption(locale: snapshot.locale ?? store.locale) ?? "")
                }
                if snapshot.overall?.score == nil {
                    Text(snapshot.overall?.availability == "partial" ? "Partly assessable" : "No assessable records yet", bundle: .module)
                        .font(Theme.body).foregroundStyle(Theme.secondary)
                }
                GlobalRankCard(store: store, locale: snapshot.locale ?? store.locale)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            DimensionRings(dimensions: snapshot.dimensions ?? [], ranking: store.ranking,
                           features: store.features, locale: snapshot.locale ?? store.locale, showsEvidence: false,
                           onSelect: { selectedDimension = $0.key })
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
        if ranking.total < 20 { return ranking.caption(locale: locale) }
        guard let percentile = ranking.percentile else { return "" }
        return locale == "zh" ? "打败了全球 \(percentile)% 的 AI 用户"
            : "You beat \(percentile)% of AI users worldwide"
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
        Group {
            VStack(alignment: .leading, spacing: 8) {
                ThemeLabel("GLOBAL")
                Text(zh ? "查看全球排名" : "View global ranking").font(Theme.title)
                if store.shareAnonymousScore {
                    if let ranking = store.ranking {
                        Text(CheckupPresentation.rankCaption(ranking, locale: locale))
                        DisclosureGroup {
                            Text(CheckupPresentation.participants(ranking, locale: locale)).font(Theme.body)
                            Text(AppScoreOut.sampleLimitation(locale: locale)).font(Theme.label)
                        } label: {
                            Image(systemName: "info.circle").accessibilityLabel(zh ? "排名说明" : "Ranking details")
                        }
                    } else {
                        Text(store.rankingCaption(locale: locale)).font(Theme.body).foregroundStyle(Theme.secondary)
                    }
                } else {
                    Text(zh ? "看看你打败了全球多少 AI 用户" : "See how many AI users you beat worldwide")
                    Button(zh ? "加入匿名排名" : "Join anonymous ranking") { showConsent = true }
                    if showConsent { ScoreConsentPanel(store: store, zh: zh, close: { showConsent = false }) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(Theme.grid * 2)
                .bauhausPanel()
        }.bauhausTheme()
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
