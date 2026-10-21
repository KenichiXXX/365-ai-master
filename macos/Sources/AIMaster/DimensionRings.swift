import SwiftUI

struct DimensionRings: View {
    let dimensions: [Dimension]

    var body: some View {
        HStack(alignment: .top) {
            ForEach(dimensions) { dimension in
                VStack(spacing: 6) {
                    ZStack {
                        Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 5)
                        Circle().trim(from: 0, to: CGFloat(dimension.score) / 100)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(String(dimension.score)).font(.caption.bold())
                    }.frame(width: 42, height: 42)
                    Text(dimension.label).font(.caption2).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity)
            }
        }
    }
}
