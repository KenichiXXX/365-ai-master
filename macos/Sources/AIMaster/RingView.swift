import SwiftUI

struct RingView: View {
    let score: Int?
    var size: CGFloat = 96
    var color: Color = Theme.accent

    var scoreText: String { score.map(String.init) ?? "—" }

    var body: some View {
        Group {
            ZStack {
                Circle().stroke(Theme.hairline, lineWidth: size * 9 / 128)
                if let score {
                    Circle().trim(from: 0, to: CGFloat(min(100, max(0, score))) / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: size * 9 / 128, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
                Text(scoreText).foregroundStyle(score == nil ? Theme.ink : size >= 128 ? Theme.accent : Theme.accentText).font(size >= 128 ? Theme.score : size >= 96 ? Theme.stat : Theme.title).monospacedDigit()
            }
            .padding(size * 9 / 256)
            .frame(width: size, height: size)
            .accessibilityLabel(score.map { "\($0) / 100" } ?? NSLocalizedString("Unknown", bundle: .module, comment: ""))
        }.bauhausTheme()
    }
}
