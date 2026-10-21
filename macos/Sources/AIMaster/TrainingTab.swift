import SwiftUI

struct TrainingTab: View {
    let snapshot: Snapshot
    @State private var selected: SkillCard?
    private var zh: Bool { snapshot.locale == "zh" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let village = snapshot.village { VillageGrid(village: village) }
            if let book = snapshot.book {
                Text(zh ? "技能图鉴 \(book.lit)/\(book.total) 已点亮" : "Skill book \(book.lit)/\(book.total) lit")
                    .font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 6) {
                    ForEach(book.cards) { card in
                        Button(action: { selected = card }) {
                            VStack(spacing: 4) {
                                Text(card.title).font(.caption).multilineTextAlignment(.center)
                                if card.how == "self" { Text(zh ? "自评" : "self").font(.system(size: 9)) }
                            }
                            .frame(maxWidth: .infinity, minHeight: 58).padding(4)
                            .background(card.lit ? Color.accentColor.opacity(0.18) : Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                                card.lit ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.4),
                                style: StrokeStyle(lineWidth: 1, dash: card.lit ? [] : [3, 3])))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .opacity(card.lit ? 1 : 0.6)
                        }.buttonStyle(.plain)
                    }
                }
            }
            let days = snapshot.streak?.days ?? 0
            Text(zh ? "连续修炼 \(days) 天" : "\(days)-day streak").font(.subheadline.bold())
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 6) {
                ForEach(snapshot.badges ?? []) { badge in
                    Text((badge.earned ? "★ " : "☆ ") + badge.title)
                        .font(.caption2).padding(6).frame(maxWidth: .infinity, minHeight: 32)
                        .background(badge.earned ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 6))
                        .opacity(badge.earned ? 1 : 0.4)
                }
            }
        }
        .sheet(item: $selected) { card in
            VStack(alignment: .leading, spacing: 12) {
                Text(card.title).font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(card.why)
                        Text(card.prompt).font(.callout).textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(zh ? "完成" : "Done") { selected = nil }
            }.padding(20).frame(width: 320, height: 340)
        }
    }
}
