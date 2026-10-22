import SwiftUI
import AppKit

struct TodaySkillTab: View {
    let snapshot: Snapshot
    @ObservedObject var store: SnapshotStore
    @State private var selectedRanking: DiscoverRanking = .skill
    private var zh: Bool { snapshot.locale == "zh" }
    private var locale: String { snapshot.locale ?? store.locale }

    init(snapshot: Snapshot, store: SnapshotStore, ranking: DiscoverRanking = .skill) {
        self.snapshot = snapshot
        self.store = store
        _selectedRanking = State(initialValue: ranking)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(zh ? "为你推荐" : "For you").font(.headline)
            if let card = snapshot.book?.today {
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.title).font(.headline)
                    Text(ActionCopy.benefit(card.why, locale: locale)).font(.body).foregroundStyle(.secondary).lineLimit(1)
                    PracticeControls(card: card, store: store, locale: locale)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            ForEach(DiscoverContent.picks(snapshot), id: \.url) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.name).font(.headline).lineLimit(1)
                    Text(ActionCopy.benefit(DiscoverContent.reason(
                        dimension: DiscoverContent.weakest(snapshot) ?? "", locale: locale), locale: locale))
                        .font(.body).foregroundStyle(.secondary).lineLimit(1)
                    Button(zh ? "查看" : "View") { openRepository(row) }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
            Text(zh ? "全球排行" : "Rankings").font(.headline)
            Picker(zh ? "全球排行" : "Rankings", selection: $selectedRanking) {
                ForEach(DiscoverRanking.allCases, id: \.self) { kind in
                    Text(kind.title(zh: zh)).tag(kind)
                }
            }.pickerStyle(.segmented).labelsHidden()
            if selectedRanking == .learnable {
                Text(zh ? "大师精选 · 新手必学" : "Master’s selection · Essentials").font(.body).foregroundStyle(.secondary)
                ForEach(Array(store.features.discoverRankings(snapshot.book?.cards ?? []).enumerated()), id: \.element.id) { index, card in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(card.title).font(.headline)
                            Text(card.why).font(.body).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text(card.lit ? (zh ? "已点亮" : "Lit") : (zh ? "待点亮" : "Unlit"))
                            .font(.body).foregroundStyle(card.lit ? Color.accentColor : .secondary)
                    }
                    Divider()
                }
            } else {
                rankingList
            }
            if !store.isPro {
                Button(zh ? "Pro 查看前 20 名" : "See the Top 20 with Pro") { store.showProSettings = true }
                    .buttonStyle(.plain).foregroundStyle(.tint)
            }
            if let tip = snapshot.dailyTip {
                VStack(alignment: .leading, spacing: 8) {
                    Label(tip.title, systemImage: "quote.opening").font(.headline)
                    Text(ActionCopy.line(tip.detail, locale: locale)).font(.body).foregroundStyle(.secondary).lineLimit(1)
                    DisclosureGroup {
                        if let source = tip.source { Text(source).font(.body) }
                        if let limitations = tip.limitations { Text(limitations).font(.body) }
                    } label: { Image(systemName: "info.circle").accessibilityLabel(zh ? "大师推荐说明" : "Master's pick details") }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var rows: [Ranking] {
        switch selectedRanking {
        case .skill: return snapshot.rankings?.skill ?? []
        case .agent: return snapshot.rankings?.agent ?? []
        case .product: return snapshot.rankings?.product ?? []
        case .learnable: return []
        }
    }

    private var rankingList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if selectedRanking == .product {
                Text(zh ? "按 GitHub 星数" : "By GitHub stars").font(.body).foregroundStyle(.secondary)
            }
            ForEach(Array(store.features.discoverRankings(rows).enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 24)
                    repositoryLink(row)
                }
                Divider()
            }
            if rows.isEmpty { Text(zh ? "暂无榜单" : "No rankings yet").foregroundStyle(.secondary) }
            if let rankings = snapshot.rankings {
                DisclosureGroup {
                    Text(rankings.footnote(locale: locale)).font(.body)
                } label: { Image(systemName: "info.circle").accessibilityLabel(zh ? "榜单来源" : "Ranking source") }
            }
        }
    }

    private func openRepository(_ row: Ranking) {
        if PublicContent.safeURL(row.url), let url = URL(string: row.url) { NSWorkspace.shared.open(url) }
    }

    private func repositoryLink(_ row: Ranking) -> some View {
        Button { openRepository(row) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(row.name).font(.headline).lineLimit(1)
                    if row.installed == true || row.installationHint == true {
                        Text(zh ? "已装" : "Installed").font(.body).padding(.horizontal, 5)
                            .background(Color.accentColor.opacity(0.1), in: Capsule())
                    }
                }
                Text(row.tagline).font(.body).foregroundStyle(.secondary).lineLimit(1)
                if row.stars != nil { Text(row.growth(locale: locale)).font(.body).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
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
                Text(card.evidenceText(locale: locale)).font(.body)
                ForEach(Array((card.steps ?? []).prefix(3).enumerated()), id: \.offset) { index, step in
                    Text(step).font(.body)
                }
                if let signal = card.expectedSignal { Text(signal).font(.body) }
                if let limitations = card.limitations { Text(limitations).font(.body) }
                if card.automaticSupported == false {
                    Text(zh ? "当前工具暂不支持自动验证" : "Automatic verification is not supported for this tool")
                        .font(.body)
                }
                if store.practiceFeedbackID == card.id, let feedback = store.triedFeedback {
                    Text(feedback == .lit ? (zh ? "已点亮" : "Lit up") : (zh ? "等待新记录" : "Waiting for new records"))
                        .font(.body)
                }
                Button(zh ? "学会了" : "Learned it") { store.markTried(card) }
                Menu {
                    Button(zh ? "开始实践" : "Start practice") { store.practice(id: card.id, operation: "start") }
                    if card.isSelfReport {
                        Button(zh ? "已尝试（自报）" : "Tried (self-reported)") { store.markTried(card) }
                    }
                    Button(zh ? "换一个" : "Skip once") { store.practice(id: card.id, operation: "skip") }
                } label: { Text("⋯") }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel(zh ? "更多操作" : "More actions")
            } label: { Image(systemName: "info.circle").accessibilityLabel(zh ? "练习说明" : "Practice details") }
            CopyButton(prompt: card.prompt, title: zh ? "复制试一下" : "Copy & try", locale: locale,
                       onCopied: { store.practice(id: card.id, operation: "copy") })
                .disabled(store.isRefreshing)
        }
    }
}
