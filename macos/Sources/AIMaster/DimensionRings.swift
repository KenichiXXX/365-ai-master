import SwiftUI

struct DimensionRings: View {
    let dimensions: [Dimension]
    var ranking: AppScoreOut? = nil
    var features = ProFeatures(isPro: false)
    var locale = "en"
    var showsEvidence = true
    var onSelect: ((Dimension) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                } label: { Text("Why this suggestion", bundle: .module).font(.caption) }
            }
        }
    }

    private func dimensionRing(_ dimension: Dimension) -> some View {
        VStack(spacing: 6) {
            RingView(score: dimension.score, size: 64)
            Text(dimension.label).font(.system(size: 11)).multilineTextAlignment(.center)
            if dimension.score != nil, let caption = features.dimensionCaption(ranking, key: dimension.key, locale: locale) {
                Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity)
    }
}


struct DimensionEvidence: View {
    let dimensions: [Dimension]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(dimensions) { dimension in
                VStack(alignment: .leading, spacing: 6) {
                    Text(dimension.label).font(.headline)
                    ForEach(Array((dimension.evidence ?? []).enumerated()), id: \.offset) { _, rule in
                        Text(rule.label ?? rule.explanation ?? "").font(.caption).fixedSize(horizontal: false, vertical: true)
                        if let n = rule.numerator, let d = rule.denominator {
                            Text("\(n.formatted()) / \(d.formatted()) · \(rule.windowDays ?? 0)d").font(.caption2)
                        }
                        Text(rule.limitation ?? "").font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
