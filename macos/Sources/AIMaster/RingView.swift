import SwiftUI

struct RingView: View {
    let score: Int?
    var size: CGFloat = 96

    var scoreText: String { score.map(String.init) ?? "—" }

    var body: some View {
        Group {
            ZStack {
                Circle().stroke(Theme.secondary.opacity(0.15), lineWidth: size / 10)
                if let score {
                    Circle().trim(from: 0, to: CGFloat(min(100, max(0, score))) / 100)
                        .stroke(Theme.blue, style: StrokeStyle(lineWidth: size / 10, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
                Text(scoreText).font(size >= 96 ? Theme.score : Theme.title)
            }
            .frame(width: size, height: size)
            .accessibilityLabel(score.map { "\($0) / 100" } ?? NSLocalizedString("Unknown", bundle: .module, comment: ""))
        }.bauhausTheme()
    }
}
