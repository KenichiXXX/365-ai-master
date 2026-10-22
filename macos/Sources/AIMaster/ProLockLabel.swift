import SwiftUI

/// Shared label for gated detail actions; the surrounding button opens the Pro sheet.
struct ProLockLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: Theme.grid) {
            Image(systemName: "lock.fill").font(Theme.label)
                .frame(width: Theme.grid * 3, height: Theme.grid * 3)
                .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: Theme.ruleWidth))
                .accessibilityHidden(true)
            Text("PRO").font(Theme.label)
            Text(title).font(Theme.body)
        }.foregroundStyle(Theme.ink)
            .accessibilityElement(children: .combine)
    }
}
