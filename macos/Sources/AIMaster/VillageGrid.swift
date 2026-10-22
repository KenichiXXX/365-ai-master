import SwiftUI

struct VillageGrid: View {
    let village: Village

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text(village.rankTitle).font(Theme.title)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: Theme.grid) {
                    ForEach(Array(village.quests.enumerated()), id: \.element.id) { index, quest in
                        VStack(alignment: .leading, spacing: Theme.grid) {
                            Text(quest.status == "passed" ? "✓" : String(index + 1)).font(Theme.title)
                            Text(quest.title).font(Theme.label).multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .padding(Theme.grid)
                        .foregroundStyle(quest.status == "locked" ? Theme.secondary : Theme.ink)
                        .background(quest.status == "passed" ? Theme.yellow : Theme.paper)
                        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(quest.status == "current" ? Theme.ink : .clear, lineWidth: 2))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))

                    }
                }
            }
        }.bauhausTheme()
    }
}
