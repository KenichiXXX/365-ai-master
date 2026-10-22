import SwiftUI
import AppKit

struct TodaySkillTab: View {
    let snapshot: Snapshot
    @ObservedObject var store: SnapshotStore
    @State private var expandedRankings: Set<String> = []
    private var zh: Bool { snapshot.locale == "zh" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let card = snapshot.book?.today {
                VStack(alignment: .leading, spacing: 10) {
                    Text(card.mode == "review" ? (zh ? "复习" : "Review") : (zh ? "新技能" : "New skill"))
                        .font(.system(size: 11).bold()).foregroundStyle(Color.accentColor)
                    Text(card.title).font(.title2.bold())
                    Text(card.why).font(.body).foregroundStyle(.secondary)
                    PracticeControls(card: card, store: store, locale: snapshot.locale ?? store.locale)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            if snapshot.book?.today == nil {
                Text(zh ? "暂无适配练习，可复习已有内容" : "No compatible exercise is available. Review an existing skill.")
            }
            rankingList(zh ? "Skill 榜" : "Skills", rows: snapshot.rankings?.skill ?? [])
            rankingList(zh ? "Agent 榜" : "Agents", rows: snapshot.rankings?.agent ?? [])
            if let tip = snapshot.dailyTip {
                VStack(alignment: .leading, spacing: 6) {
                    Text(zh ? "大师一句话" : "Master's tip").font(.headline)
                    Text(tip.title).font(.title2.bold())
                    Text(tip.detail).font(.body).foregroundStyle(.secondary)
                    if let source = tip.source, !source.isEmpty { Text(source).font(.system(size: 11)).foregroundStyle(.secondary) }
                }
            }
            if !snapshot.relevantToolUpdates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(zh ? "与你的工具有关的更新" : "Updates for your tools").font(.headline)
                    ForEach(snapshot.relevantToolUpdates) { update in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(update.summary)
                            Text(DisplayDate.short(update.releasedAt, locale: snapshot.locale ?? store.locale)).font(.caption).foregroundStyle(.secondary)
                            if let card = snapshot.book?.cards.first(where: { $0.id == update.practiceId }) {
                                DisclosureGroup(card.title) {
                                    PracticeControls(card: card, store: store, locale: snapshot.locale ?? store.locale)
                                }
                            }
                            if PublicContent.safeURL(update.sourceUrl), let url = URL(string: update.sourceUrl) {
                                Link(zh ? "官方来源" : "Official source", destination: url)
                            }
                        }
                    }
                }
            }
            if !(snapshot.book?.yesterday ?? []).isEmpty {
                DisclosureGroup(zh ? "昨天的练习" : "Yesterday’s practice") {
                    ForEach(snapshot.book?.yesterday ?? []) { attempt in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(snapshot.book?.cards.first { $0.id == attempt.skillId }?.title ?? (zh ? "复习" : "Review"))
                                .font(.headline)
                            Text(attempt.status == "observed"
                                 ? (zh ? "昨天的动作已有后续记录" : "A later record was found for yesterday's action")
                                 : attempt.status == "not_yet" ? (zh ? "尚未观察到" : "Not observed yet")
                                 : (zh ? "未获得新数据" : "No new data received"))
                                .font(.callout)
                            Button(zh ? "停止追踪" : "Stop tracking") {
                                store.practice(id: attempt.attemptId, operation: "stop")
                            }.disabled(store.isRefreshing)
                        }
                    }
                }
            }

        }
    }

    private func rankingList(_ title: String, rows: [Ranking]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(title) · \(store.features.rankings(rows, expanded: expandedRankings.contains(title)).count)").font(.headline)
            ForEach(Array(store.features.rankings(rows, expanded: expandedRankings.contains(title)).enumerated()), id: \.offset) { _, row in
                Button(action: {
                    if PublicContent.safeURL(row.url), let url = URL(string: row.url) {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.name).font(.headline).lineLimit(1)
                            Text(row.tagline).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                            if row.stars != nil || row.installed == true {
                                HStack {
                                    Text(row.growth(locale: snapshot.locale ?? "en"))
                                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    if row.installed == true {
                                        Text(zh ? "已装" : "Installed").font(.caption2)
                                            .padding(.horizontal, 5).background(Color.accentColor.opacity(0.1), in: Capsule())
                                    }
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Divider()
            }
            if rows.count > 5 {
                Button(expandedRankings.contains(title) && store.isPro ? (zh ? "收起" : "Show less") : (zh ? "展开全部" : "Show all")) {
                    if store.isPro {
                        if expandedRankings.contains(title) { expandedRankings.remove(title) }
                        else { expandedRankings.insert(title) }
                    } else { store.showProSettings = true }
                }.buttonStyle(.plain).foregroundStyle(.tint)
            }
            if let rankings = snapshot.rankings {
                Text(rankings.footnote(locale: snapshot.locale ?? "en"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

struct PracticeControls: View {
    let card: SkillCard
    @ObservedObject var store: SnapshotStore
    let locale: String
    private var zh: Bool { locale == "zh" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DisclosureGroup {
                Text(card.evidenceText(locale: locale)).font(.caption)
                ForEach(Array((card.steps ?? []).enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)").font(.callout)
                }
                if let signal = card.expectedSignal { Text(signal).font(.caption) }
                if let limitations = card.limitations { Text(limitations).font(.caption) }
                if card.automaticSupported == false {
                    Text(zh ? "当前工具暂不支持自动验证" : "Automatic verification is not supported for this tool")
                        .font(.caption)
                }
            } label: { Image(systemName: "info.circle").accessibilityLabel(zh ? "练习说明" : "Practice details") }
            HStack {
                CopyButton(prompt: card.prompt, title: zh ? "复制给 Claude 的指令" : "Copy prompt", locale: locale,
                           onCopied: { store.practice(id: card.id, operation: "copy") })
                Button(zh ? "做完了，帮我检查" : "Check now") { store.refresh() }
                Menu {
                    Button(zh ? "开始实践" : "Start practice") { store.practice(id: card.id, operation: "start") }
                    if card.isSelfReport {
                        Button(zh ? "已尝试（自报）" : "Tried (self-reported)") { store.markTried(card) }
                    }
                    Button(zh ? "换一个" : "Skip once") { store.practice(id: card.id, operation: "skip") }
                } label: { Text("⋯") }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel(zh ? "更多操作" : "More actions")
            }.controlSize(.small).disabled(store.isRefreshing)
        }
    }
}
