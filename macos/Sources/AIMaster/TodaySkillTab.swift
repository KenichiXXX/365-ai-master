import SwiftUI
import AppKit

struct TodaySkillTab: View {
    let snapshot: Snapshot
    @ObservedObject var store: SnapshotStore
    private var zh: Bool { snapshot.locale == "zh" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let card = snapshot.book?.today {
                VStack(alignment: .leading, spacing: 10) {
                    if !card.lit {
                        Text(zh ? "NEW · 你还没用过" : "New for you")
                            .font(.system(size: 11).bold()).foregroundStyle(Color.accentColor)
                    }
                    Text(card.title).font(.title2.bold())
                    Text(card.why).font(.body).foregroundStyle(.secondary)
                    HStack {
                        CopyButton(prompt: card.prompt, title: zh ? "复制试一下" : "Copy and try",
                                   locale: snapshot.locale ?? store.locale)
                        Button(zh ? "试过了" : "I tried it") { store.markTried(card) }
                            .disabled(store.isRefreshing)
                    }.controlSize(.small)
                    if let feedback = store.triedFeedback {
                        Text(feedback == .lit ? (zh ? "已点亮 ✓" : "Lit ✓")
                             : (zh ? "还没在日志里看到它——真正用一次后会自动点亮"
                                : "Not seen in your logs yet — it lights up automatically after you use it once"))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            rankingList(zh ? "今日 Skill 榜" : "Today's skills", rows: snapshot.rankings?.skill ?? [])
            rankingList(zh ? "今日 Agent 榜" : "Today's agents", rows: snapshot.rankings?.agent ?? [])
            if let tip = snapshot.dailyTip {
                VStack(alignment: .leading, spacing: 6) {
                    Text(zh ? "大师一句话" : "Master's tip").font(.headline)
                    Text(tip.title).font(.title2.bold())
                    Text(tip.detail).font(.body).foregroundStyle(.secondary)
                    if let source = tip.source, !source.isEmpty { Text(source).font(.system(size: 11)).foregroundStyle(.secondary) }
                }
            }
        }
    }

    private func rankingList(_ title: String, rows: [Ranking]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Button(action: {
                    if let url = URL(string: row.url), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.name).font(.headline)
                            Text(row.tagline).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !row.growth(locale: snapshot.locale ?? "en").isEmpty {
                                Text(row.growth(locale: snapshot.locale ?? "en"))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        if row.installed {
                            Text(zh ? "已装" : "Installed")
                                .font(.system(size: 11)).padding(.horizontal, 5).padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.18), in: Capsule()).fixedSize()
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Divider()
            }
            if let source = snapshot.rankings?.source, !source.isEmpty {
                Text((zh ? "数据：" : "Data: ") + source)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}
