import SwiftUI

struct DimensionRings: View {
    let dimensions: [Dimension]
    var ranking: AppScoreOut? = nil
    var features = ProFeatures(isPro: false)
    var locale = "en"
    var showsEvidence = true
    var onSelect: ((Dimension) -> Void)? = nil

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: Theme.grid) {
                HStack(alignment: .top) {
                    ForEach(dimensions) { dimension in
                        if let onSelect {
                            Button { onSelect(dimension) } label: {
                                dimensionRing(dimension)
                            }.buttonStyle(.plain)
                                .accessibilityLabel(dimension.label + (locale == "zh" ? "，查看详情" : ", view details"))
                        } else {
                            dimensionRing(dimension)
                        }
                    }
                }
                if showsEvidence, dimensions.contains(where: { $0.evidence?.isEmpty == false }) {
                    DisclosureGroup {
                        DimensionEvidence(dimensions: dimensions)
                    } label: { Text("Why this suggestion", bundle: .module).font(Theme.label) }
                }
            }
        }.bauhausTheme()
    }

    private func dimensionRing(_ dimension: Dimension) -> some View {
        VStack(alignment: .leading, spacing: Theme.grid) {
            RingView(score: dimension.score, size: 64, color: Theme.dimension(dimension.key))
            Text(dimension.label).font(Theme.label).multilineTextAlignment(.leading)
            if dimension.score != nil, let caption = features.dimensionCaption(ranking, key: dimension.key, locale: locale) {
                Text(caption).font(Theme.label).foregroundStyle(Theme.secondary)
            }
        }.frame(maxWidth: .infinity)
    }
}


struct DimensionEvidence: View {
    let dimensions: [Dimension]

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(dimensions) { dimension in
                    VStack(alignment: .leading, spacing: Theme.grid) {
                        Text(dimension.label).font(Theme.title)
                        ForEach(Array((dimension.evidence ?? []).enumerated()), id: \.offset) { _, rule in
                            Text(rule.label ?? rule.explanation ?? "").font(Theme.label).fixedSize(horizontal: false, vertical: true)
                            if let n = rule.numerator, let d = rule.denominator {
                                Text("\(n.formatted()) / \(d.formatted()) · \(rule.windowDays ?? 0)d").font(Theme.label)
                            }
                            Text(rule.limitation ?? "").font(Theme.label).foregroundStyle(Theme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }.bauhausTheme()
    }
}
