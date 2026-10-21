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
                    Button(zh ? "换一个" : "Skip once") { store.practice(id: card.id, operation: "skip") }
                        .disabled(store.isRefreshing)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            if snapshot.book?.today == nil {
                Text(zh ? "暂无适配练习，可复习已有内容" : "No compatible exercise is available. Review an existing skill.")
            }
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
            VStack(alignment: .leading, spacing: 6) {
                Text(zh ? "与你的工具有关的更新" : "Updates for your tools").font(.headline)
                if snapshot.relevantToolUpdates.isEmpty {
                    Text(zh ? "暂无与你有关的更新" : "No relevant updates").foregroundStyle(.secondary)
                }
                ForEach(snapshot.relevantToolUpdates) { update in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(update.summary)
                        Text(update.releasedAt).font(.caption).foregroundStyle(.secondary)
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
                            Text(row.name).font(.headline)
                            Text(row.tagline).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(row.compatibilityLabel(locale: snapshot.locale ?? "en")).font(.caption).foregroundStyle(.secondary)
                            if let category = row.taskCategory { Text(category).font(.caption) }
                            if let source = row.sourceUrl { Text(source + (row.sourceDate.map { " · " + $0 } ?? "")).font(.caption).foregroundStyle(.secondary) }
                            if row.installationHint == true || row.installed == true {
                                Text(zh ? "发现同名安装项，未验证" : "Matching installation name found; unverified")
                                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            if let sourceType = row.sourceType {
                                Text(sourceType == "curated" ? (zh ? "精选内容" : "Curated content") : sourceType == "repository" ? (zh ? "仓库来源" : "Repository source") : (zh ? "目录来源" : "Catalog source")).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(row.caution ?? (zh ? "安装前请核对权限与来源" : "Check permissions and source before installing")).font(.caption).foregroundStyle(.secondary)
                            if !row.growth(locale: snapshot.locale ?? "en").isEmpty {
                                Text(row.growth(locale: snapshot.locale ?? "en"))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
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
                Text(rankings.sourceLabel(locale: snapshot.locale ?? "en", stale: store.contentStale))
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
            Text(card.evidenceText(locale: locale)).font(.caption).foregroundStyle(.secondary)
            ForEach(Array((card.steps ?? []).enumerated()), id: \.offset) { index, step in
                Text("\(index + 1). \(step)").font(.callout)
            }
            if let signal = card.expectedSignal { Text(signal).font(.caption) }
            if let limitations = card.limitations { Text(limitations).font(.caption).foregroundStyle(.secondary) }
            if card.automaticSupported == false {
                Text(zh ? "当前工具暂不支持自动验证" : "Automatic verification is not supported for this tool")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                CopyButton(prompt: card.prompt, title: zh ? "复制试一下" : "Copy and try", locale: locale,
                           onCopied: { store.practice(id: card.id, operation: "copy") })
                Button(zh ? "开始实践" : "Start practice") { store.practice(id: card.id, operation: "start") }
                if card.isSelfReport {
                    Button(zh ? "已尝试（自报）" : "Tried (self-reported)") { store.markTried(card) }
                }
            }.controlSize(.small).disabled(store.isRefreshing)
            if store.feedback(for: card.id) != nil {
                Text(card.evidenceText(locale: locale)).font(.caption)
            }
        }
    }
}
