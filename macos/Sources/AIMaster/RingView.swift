import SwiftUI

struct RingView: View {
    let score: Int
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.15), lineWidth: size / 10)
            Circle().trim(from: 0, to: CGFloat(min(100, max(0, score))) / 100)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: size / 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(String(score)).font(.system(size: size / 3, weight: .semibold, design: .rounded))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(score) / 100")
    }
}
