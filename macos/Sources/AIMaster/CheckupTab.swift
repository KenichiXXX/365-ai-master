import SwiftUI
import ServiceManagement

struct CheckupTab: View {
    let snapshot: Snapshot
    @ObservedObject var store: SnapshotStore

    @State private var loginError = false
    private var zh: Bool { snapshot.locale == "zh" }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !store.onboarded {
                VStack(alignment: .leading, spacing: 10) {
                    Text(zh ? "365 AI Master 每天读你本机的 AI 使用记录（只读、不上传），给你一个提升动作和一个新技能。"
                         : "365 AI Master reads your local AI usage records each day (read-only, never uploaded) and gives you one improvement action and one new skill.")
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
                    Text(progressLine).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity).padding(.top, 8)
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
