import SwiftUI
import ServiceManagement

struct CheckupTab: View {
    let snapshot: Snapshot
    @ObservedObject var store: SnapshotStore

    @State private var loginError = false
    @State private var showScoreConsent = false
    private var zh: Bool { snapshot.locale == "zh" }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !store.onboarded {
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
                        Button(zh ? "知道了" : "Got it") { store.dismissOnboarding() }
                        Button(zh ? "参与匿名排名" : "Join ranking") { showScoreConsent = true }
                    }
                    if loginError {
                        Text("Login item unavailable", bundle: .module).font(.system(size: 11)).foregroundStyle(.orange)
                    }
                }.padding(12).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            VStack(spacing: 10) {
                RingView(score: snapshot.overall?.score ?? 0, size: 150)
                if let village = snapshot.village {
                    Text(village.rankTitle).font(.title2.bold())
                    if store.shareAnonymousScore {
                        if let ranking = store.ranking {
                            Text(ranking.caption(locale: snapshot.locale ?? store.locale))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    } else {
                        Button(zh ? "看看你击败了全球多少 AI 用户 →" : "See how you rank worldwide →") {
                            showScoreConsent = true
                        }.buttonStyle(.plain).foregroundStyle(.tint).font(.system(size: 11))
                    }
                    Text(progressLine).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity).padding(.top, 8)
            if showScoreConsent {
                VStack(alignment: .leading, spacing: 10) {
                    Text(ScoreConsent.explanation(locale: snapshot.locale ?? store.locale)).font(.callout)
                    HStack {
                        Button(zh ? "允许" : "Allow") {
                            store.shareAnonymousScore = true
                            store.dismissOnboarding()
                            showScoreConsent = false
                        }
                        Button(zh ? "暂不" : "Not now") { showScoreConsent = false }
                    }
                }.padding(12).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            DimensionRings(dimensions: snapshot.dimensions ?? [])
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


enum ScoreConsent {
    static func explanation(locale: String) -> String {
        locale == "zh" ? "开启后，每天最多一次上传：总分和四个维度分，以及一个随机编号。不上传任何使用记录、文件或对话。随时可以关闭。"
            : "When on, once a day at most we upload your overall score, your four dimension scores, and a random ID. Never your usage logs, files, or conversations. Turn it off anytime."
    }
}
