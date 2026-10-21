import SwiftUI

struct RingView: View {
    let score: Int?
    var size: CGFloat = 96

    var scoreText: String { score.map(String.init) ?? "—" }

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.15), lineWidth: size / 10)
            if let score {
                Circle().trim(from: 0, to: CGFloat(min(100, max(0, score))) / 100)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: size / 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(scoreText).font(.system(size: size / 3, weight: .semibold, design: .rounded))
        }
        .frame(width: size, height: size)
        .accessibilityLabel(score.map { "\($0) / 100" } ?? NSLocalizedString("Unknown", bundle: .module, comment: ""))
    }
}
