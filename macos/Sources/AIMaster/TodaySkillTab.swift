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
                            .font(.caption.bold()).foregroundStyle(Color.accentColor)
                    }
                    Text(card.title).font(.title3.bold())
                    Text(card.why).font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button(zh ? "复制试一下" : "Copy and try") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(card.prompt, forType: .string)
                        }
                        Button(zh ? "试过了" : "I tried it") { store.markTried(card) }
                            .disabled(store.isRefreshing)
                    }.controlSize(.small)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            rankingList(zh ? "今日 Skill 榜" : "Today's skills", rows: snapshot.rankings?.skill ?? [])
            rankingList(zh ? "今日 Agent 榜" : "Today's agents", rows: snapshot.rankings?.agent ?? [])
            if let tip = snapshot.dailyTip {
                VStack(alignment: .leading, spacing: 6) {
                    Text(zh ? "大师一句话" : "Master's tip").font(.headline)
                    Text(tip.title).font(.subheadline.bold())
                    Text(tip.detail).font(.callout).foregroundStyle(.secondary)
                    if let source = tip.source, !source.isEmpty { Text(source).font(.caption2).foregroundStyle(.secondary) }
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
                            Text(row.name).font(.subheadline.bold())
                            Text(row.tagline).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Text(row.installed ? (zh ? "已装" : "Installed") : (zh ? "未装" : "Not installed"))
                            .font(.system(size: 9)).padding(.horizontal, 5).padding(.vertical, 3)
                            .background(row.installed ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1),
                                        in: Capsule()).fixedSize()
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Divider()
            }
            if let source = snapshot.rankings?.source, !source.isEmpty {
                Text((zh ? "数据：" : "Data: ") + source)
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
