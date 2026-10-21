import SwiftUI

struct VillageGrid: View {
    let village: Village

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(village.rankTitle).font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 6) {
                ForEach(Array(village.quests.enumerated()), id: \.element.id) { index, quest in
                    VStack(spacing: 4) {
                        Text(quest.status == "passed" ? "✓" : String(index + 1)).font(.headline)
                        Text(quest.title).font(.system(size: 11)).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .padding(4)
                    .background(quest.status == "passed" ? Color.accentColor.opacity(0.22) : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(quest.status == "current" ? Color.accentColor : .clear, lineWidth: 2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .opacity(quest.status == "locked" ? 0.4 : 1)
                }
            }
        }
    }
}
