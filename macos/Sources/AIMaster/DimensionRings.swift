import SwiftUI

struct DimensionRings: View {
    let dimensions: [Dimension]

    var body: some View {
        HStack(alignment: .top) {
            ForEach(dimensions) { dimension in
                VStack(spacing: 6) {
                    RingView(score: dimension.score, size: 64)
                    Text(dimension.label).font(.system(size: 11)).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity)
            }
        }
    }
}
