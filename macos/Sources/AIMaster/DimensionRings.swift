import SwiftUI

struct DimensionRings: View {
    let dimensions: [Dimension]
    var ranking: AppScoreOut? = nil
    var features = ProFeatures(isPro: false)
    var locale = "en"

    var body: some View {
        HStack(alignment: .top) {
            ForEach(dimensions) { dimension in
                VStack(spacing: 6) {
                    RingView(score: dimension.score, size: 64)
                    Text(dimension.label).font(.system(size: 11)).multilineTextAlignment(.center)
                    if let caption = features.dimensionCaption(ranking, key: dimension.key, locale: locale) {
                        Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity)
            }
        }
    }
}
