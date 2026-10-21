import SwiftUI

struct CheckupTab: View {
    let snapshot: Snapshot
    @ObservedObject var store: SnapshotStore

    @State private var showRankingConsent = false
    private var zh: Bool { snapshot.locale == "zh" }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 10) {
                RingView(score: snapshot.overall?.score, size: 150)
                if snapshot.overall?.score == nil {
                    Text(snapshot.overall?.availability == "partial" ? "Partly assessable" : "No assessable records yet", bundle: .module)
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let village = snapshot.village {
                    Text(village.rankTitle).font(.title2.bold())
                    if store.shareAnonymousScore && snapshot.hasEvaluableScores {
                        RankingSummary(caption: store.rankingCaption(locale: snapshot.locale ?? store.locale),
                                       ranking: store.ranking, locale: snapshot.locale ?? store.locale)
                    } else if snapshot.hasEvaluableScores {
                        Button(zh ? "看看你击败了全球多少 AI 用户 →" : "See how you rank worldwide →") {
                            showRankingConsent = true
                        }.buttonStyle(.plain).foregroundStyle(.tint).font(.system(size: 11))
                        if showRankingConsent {
                            ScoreConsentPanel(store: store, zh: zh, close: { showRankingConsent = false })
                        }
                    }
                    Text(progressLine).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity).padding(.top, 8)
            DimensionRings(dimensions: snapshot.dimensions ?? [], ranking: store.ranking,
                           features: store.features, locale: snapshot.locale ?? store.locale)
            if store.features.growthCurve, let growth = snapshot.growth {
                GrowthCurve(growth: growth, zh: zh)
            }
            if store.features.weeklyReview {
                Button(zh ? "本周复盘" : "Weekly review") { store.openWeeklyReview() }
            }
            DisclosureGroup {
                FirstPracticeView(store: store)
            } label: { Text("Practice manually", bundle: .module) }
            Divider()
            if let tip = snapshot.todayTip { TipCard(tip: tip, store: store) }
            if let usage = snapshot.usageSummary {
                Text(usage.caption(locale: snapshot.locale ?? store.locale))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var progressLine: String {
        let village = snapshot.village
        let current = village?.quests.firstIndex(where: { $0.key == village?.current }).map { $0 + 1 }
            ?? village?.quests.count ?? 0
        let days = snapshot.streak?.days ?? 0
        return snapshot.locale == "zh" ? "新手村第 \(current) 关 · 连续 \(days) 天"
            : "Village quest \(current) · \(days)-day streak"
    }
}


struct ScoreConsentPanel: View {
    @ObservedObject var store: SnapshotStore
    let zh: Bool
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ScoreConsent.explanation(locale: zh ? "zh" : "en")).font(.callout)
            HStack {
                Button(zh ? "允许" : "Allow") {
                    Task { await store.allowScoreSharing() }
                    close()
                }
                Button(zh ? "暂不" : "Not now", action: close)
            }
        }.padding(12).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
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
        VStack(spacing: 6) {
            Text(caption)
            if let ranking {
                Text(ranking.participationCaption(locale: locale))
                Text(AppScoreOut.sampleLimitation(locale: locale))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.font(.system(size: 11)).foregroundStyle(.secondary)
    }
}
