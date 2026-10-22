import SwiftUI

struct TrainingTab: View {
    let snapshot: Snapshot
    @ObservedObject var store: SnapshotStore
    @State private var showShareCard = false
    @State private var selected: String?
    private var zh: Bool { snapshot.locale == "zh" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let game = snapshot.trainingGame { TrainingGameView(game: game, store: store, zh: zh) }
            Button(shareCopy("Share my practice", snapshot.locale ?? "en")) { showShareCard = true }
                .sheet(isPresented: $showShareCard) { ShareCard(snapshot: snapshot, store: store) }
            HStack(spacing: 8) {
                stat(zh ? "新手村" : "Village",
                     value: "\(snapshot.village?.quests.filter { $0.status == "passed" }.count ?? 0)/9")
                stat(zh ? "技能图鉴" : "Skill book",
                     value: "\(snapshot.book?.lit ?? 0)/\(snapshot.book?.total ?? 0)")
                stat(zh ? "AI 使用记录" : "AI usage",
                     value: zh ? "\(snapshot.streak?.days ?? 0) 天" : "\(snapshot.streak?.days ?? 0) days")
            }
            if let label = snapshot.streak?.label {
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            if let calendar = snapshot.book?.practiceCalendar {
                DisclosureGroup(zh ? "实践记录" : "Practice history") { PracticeCalendar(data: calendar) }
            }
            if let village = snapshot.village {
                DisclosureGroup(zh ? "新手村之路" : "Village path") {
                    VStack(alignment: .leading, spacing: 12) {
                        villagePath(village)
                        if let quest = village.quests.first(where: { $0.key == village.current }) {
                            DisclosureGroup(quest.title) {
                                Text(quest.evidenceLabel ?? NSLocalizedString("Historical record, not evidence of this practice", bundle: .module, comment: ""))
                                    .font(.caption)
                                FirstPracticeView(store: store)
                            }
                        }
                        if village.current == nil {
                            Text(zh ? "出师 ✓" : "Graduated ✓")
                                .font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        } else if let tip = snapshot.todayTip, tip.source.kind == "quest",
                                  tip.source.ref == village.current {
                            TipCard(tip: tip, store: store)
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            if let book = snapshot.book {
                DisclosureGroup(zh ? "技能图鉴" : "Skill book") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(zh ? "配置存在 \(book.configurationCount ?? 0) · 自报 \(book.selfReportCount ?? 0)"
                             : "Configuration \(book.configurationCount ?? 0) · Self-reported \(book.selfReportCount ?? 0)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text((book.groups ?? []).map { "\($0.title) \($0.lit)/\($0.total)" }.joined(separator: " · "))
                            .font(.callout).foregroundStyle(.secondary)
                        ForEach(book.groups ?? []) { group in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(book.cards.filter { $0.level == group.level }) { card in
                                        skillRow(card)
                                    }
                                }.padding(.top, 8)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(group.title) \(group.lit)/\(group.total)").font(.subheadline.bold())
                                    Text(missingSummary(group, book: book))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }.padding(10).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(zh ? "下一枚徽章" : "Next badge").font(.headline)
                    if let badge = book.nextBadge {
                        HStack {
                            Text(badge.title)
                            Spacer()
                            Text("\(badge.have)/\(badge.need)").monospacedDigit()
                        }
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.secondary.opacity(0.15))
                                Capsule().fill(Color.accentColor)
                                    .frame(width: geometry.size.width * Double(badge.have) / Double(badge.need))
                            }
                        }.frame(height: 6)
                            .accessibilityLabel(badge.title)
                            .accessibilityValue("\(badge.have)/\(badge.need)")
                    } else {
                        Text(zh ? "徽章已集齐 ✓" : "All badges earned ✓")
                    }
                    let earned = (snapshot.badges ?? []).filter(\.earned).map(\.title)
                    Text(earned.isEmpty ? (zh ? "尚未获得徽章" : "No badges yet") : earned.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(12).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func stat(_ title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }.frame(maxWidth: .infinity).padding(10)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func villagePath(_ village: Village) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(village.quests.enumerated()), id: \.element.id) { index, quest in
                if index > 0 {
                    Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 2)
                }
                Text(quest.status == "passed" ? "✓" : String(index + 1))
                    .font(.caption.bold()).frame(width: 28, height: 28)
                    .foregroundStyle(quest.status == "passed" ? Color.white :
                                        quest.status == "current" ? Color.accentColor : Color.secondary)
                    .background(quest.status == "passed" ? Color.accentColor : Color.secondary.opacity(0.08), in: Circle())
                    .overlay(Circle().strokeBorder(quest.status == "current" ? Color.accentColor : .clear, lineWidth: 2))
                    .accessibilityLabel("\(index + 1). \(quest.title), \(quest.status)")
            }
        }
    }

    private func missingSummary(_ group: SkillGroup, book: SkillBook) -> String {
        if group.missing.isEmpty { return zh ? "已全部点亮 ✓" : "All lit ✓" }
        if !zh { return "\(group.missing.count) to go" }
        let titles = group.missing.prefix(2).compactMap { id in book.cards.first { $0.id == id }?.title }
        return "还差：" + titles.joined(separator: "、") + (group.missing.count > 2 ? "…" : "")
    }

    private func skillRow(_ card: SkillCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                selected = selected == card.id ? nil : card.id
                if selected == card.id { store.practice(id: card.id, operation: "seen") }
            }) {
                HStack {
                    Text(card.lit ? "✓" : "○").foregroundStyle(card.lit ? Color.accentColor : Color.secondary)
                    Text(card.title)
                    Spacer()
                    Text(card.evidenceText(locale: snapshot.locale ?? store.locale)).font(.caption).foregroundStyle(.secondary)
                    Image(systemName: selected == card.id ? "chevron.up" : "chevron.down").font(.caption)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if selected == card.id {
                SkillCardDetails(card: card, todayID: snapshot.book?.today?.id,
                                 store: store, locale: snapshot.locale ?? store.locale)
            }
        }.padding(.vertical, 4)
    }
}

struct SkillCardDetails: View {
    let card: SkillCard
    let todayID: String?
    @ObservedObject var store: SnapshotStore
    let locale: String

    var body: some View {
        if store.features.canLearn(card, todayID: todayID) {
            VStack(alignment: .leading, spacing: 8) {
                Text(card.why).font(.callout).foregroundStyle(.secondary)
                Text(card.prompt).font(.callout).textSelection(.enabled)
                PracticeControls(card: card, store: store, locale: locale)
            }
        } else {
            Button(locale == "zh" ? "Pro 可随时选学这张卡" : "Pro: learn any card anytime") {
                store.showProSettings = true
            }.buttonStyle(.plain).foregroundStyle(.tint)
        }
    }
}
