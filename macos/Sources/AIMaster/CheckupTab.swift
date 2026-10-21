import SwiftUI
import ServiceManagement

struct CheckupTab: View {
    let snapshot: Snapshot
    @ObservedObject var store: SnapshotStore

    @State private var consentSource: ScoreConsentSource?
    private var zh: Bool { snapshot.locale == "zh" }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !store.onboarded {
                CheckupOnboardingBanner(store: store, zh: zh, consentSource: consentSource,
                                        requestConsent: { consentSource = .banner },
                                        closeConsent: { consentSource = nil })
            }
            VStack(spacing: 10) {
                RingView(score: snapshot.overall?.score, size: 150)
                if snapshot.overall?.score == nil {
                    Text(snapshot.overall?.availability == "partial" ? "Partly assessable" : "No assessable records yet", bundle: .module)
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let village = snapshot.village {
                    Text(village.rankTitle).font(.title2.bold())
                    if store.shareAnonymousScore && snapshot.hasEvaluableScores {
                        Text(store.rankingCaption(locale: snapshot.locale ?? store.locale))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    } else if snapshot.hasEvaluableScores {
                        Button(zh ? "看看你击败了全球多少 AI 用户 →" : "See how you rank worldwide →") {
                            consentSource = .rankLink
                        }.buttonStyle(.plain).foregroundStyle(.tint).font(.system(size: 11))
                        if consentSource == .rankLink {
                            ScoreConsentPanel(store: store, zh: zh, close: { consentSource = nil })
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


enum ScoreConsentSource { case banner, rankLink }

struct CheckupOnboardingBanner: View {
    @ObservedObject var store: SnapshotStore
    let zh: Bool
    let consentSource: ScoreConsentSource?
    let requestConsent: () -> Void
    let closeConsent: () -> Void
    @State private var loginError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(zh ? "365 AI Master 每天读你本机的 AI 使用记录（只读，默认不上传任何数据），给你一个提升动作和一个新技能。"
                 : "365 AI Master reads your local AI usage every day (read-only; nothing is uploaded unless you opt in) and gives you one thing to improve and one new skill.")
                .font(.body)
            HStack {
                Button(zh ? "开机自动启动" : "Launch at login") {
                    do {
                        try SMAppService.mainApp.register()
                        if SMAppService.mainApp.status == .enabled { store.dismissOnboarding() }
                        else { loginError = true }
                    } catch { loginError = true }
                }
                if consentSource != .banner {
                    Button(zh ? "知道了" : "Got it") { store.dismissOnboarding() }
                }
                Button(zh ? "参与匿名排名" : "Join ranking", action: requestConsent)
            }
            if consentSource == .banner {
                ScoreConsentPanel(store: store, zh: zh, close: closeConsent)
            }
            if loginError {
                Text("Login item unavailable", bundle: .module).font(.system(size: 11)).foregroundStyle(.orange)
            }
        }.padding(12).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
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
        locale == "zh" ? "开启后，每天最多一次上传：总分和四个维度分，以及一个随机编号。不上传任何使用记录、文件或对话。随时可以关闭。"
            : "When on, once a day at most we upload your overall score, your four dimension scores, and a random ID. Never your usage logs, files, or conversations. Turn it off anytime."
    }
}
