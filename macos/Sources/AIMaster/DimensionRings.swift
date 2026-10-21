import SwiftUI

struct DimensionRings: View {
    let dimensions: [Dimension]

    var body: some View {
        HStack(alignment: .top) {
            ForEach(dimensions) { dimension in
                VStack(spacing: 6) {
                    RingView(score: dimension.score, size: 42)
                    Text(dimension.label).font(.caption2).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity)
            }
        }
    }
}
