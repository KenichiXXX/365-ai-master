import SwiftUI

enum Theme {
    static let grid: CGFloat = 4
    static let cornerRadius: CGFloat = 16
    static let outerRadius: CGFloat = 22
    static let listRadius: CGFloat = 12
    static let buttonRadius: CGFloat = 9
    static let pagePadding: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let sectionGap: CGFloat = 16
    static let ruleWidth: CGFloat = 1
    static let feedbackDuration: Double = 0.14

    static func background(for scheme: ColorScheme) -> Color {
        color(scheme == .dark ? 0x242E39 : 0xEDF2F5).opacity(scheme == .dark ? 0.91 : 0.86)
    }
    static func foreground(for scheme: ColorScheme) -> Color { color(scheme == .dark ? 0xF0F4F8 : 0x1D2933) }
    static let paper = adaptive(light: 0xEDF2F5, dark: 0x242E39, lightAlpha: 0.86, darkAlpha: 0.91)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x3A4858, lightAlpha: 0.67, darkAlpha: 0.69)
    static let ink = adaptive(light: 0x1D2933, dark: 0xF0F4F8)
    static let secondary = adaptive(light: 0x596773, dark: 0xB4C0CC)
    static let hairline = adaptive(light: 0x41566C, dark: 0xC4D7EC, lightAlpha: 0.15, darkAlpha: 0.17)
    static let accent = adaptive(light: 0x007F75, dark: 0x65DCC6)
    static let accentSurface = accent.opacity(0.12)
    static let onAccent = adaptive(light: 0xFFFFFF, dark: 0x242E39)

    static let body = Font.system(size: 13)
    static let title = Font.system(size: 20, weight: .semibold)
    static let sectionTitle = Font.system(size: 13, weight: .semibold)
    static let label = Font.system(size: 11)
    static let stat = Font.system(size: 40, weight: .medium)
    static let score = Font.system(size: 64, weight: .medium)
    static func proTitle(isPro: Bool) -> String { isPro ? "PRO ✓" : "PRO ↗" }

    private static func color(_ hex: Int) -> Color { Color(nsColor: nsColor(hex)) }
    private static func nsColor(_ hex: Int, alpha: Double = 1) -> NSColor {
        NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: alpha)
    }
    private static func adaptive(light: Int, dark: Int, lightAlpha: Double = 1, darkAlpha: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return nsColor(isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

struct WindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct MasterWindowBackground: View {
    var body: some View {
        WindowMaterial().overlay(Theme.paper).allowsHitTesting(false)
    }
}

enum MasterTab: Int, CaseIterable {
    case me, picks, training
    func title(locale: String) -> String {
        switch self {
        case .me: return locale == "zh" ? "● 我" : "● Me"
        case .picks: return locale == "zh" ? "■ 大师推荐" : "■ Master's picks"
        case .training: return locale == "zh" ? "▲ 修炼" : "▲ Training"
        }
    }
}

struct MasterTabBar: View {
    @Binding var selection: Int
    let locale: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            ForEach(MasterTab.allCases, id: \.rawValue) { tab in
                Button { selection = tab.rawValue } label: {
                    Text(tab.title(locale: locale)).font(Theme.body)
                        .fontWeight(selection == tab.rawValue ? .semibold : .regular)
                        .foregroundStyle(selection == tab.rawValue ? Theme.ink : Theme.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .background {
                            if selection == tab.rawValue {
                                RoundedRectangle(cornerRadius: Theme.buttonRadius)
                                    .fill(Theme.surface)
                                    .shadow(color: Theme.ink.opacity(0.08), radius: 2, y: 1)
                            }
                        }
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(selection == tab.rawValue ? .isSelected : [])
                    .accessibilityIdentifier("tab-\(tab.rawValue)")
            }
        }.padding(3).background(Theme.hairline, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
            .animation(reduceMotion ? nil : .easeInOut(duration: Theme.feedbackDuration), value: selection)
    }
}

struct ThemeLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View { Text(title).font(Theme.label).foregroundStyle(Theme.secondary) }
}

struct TrendMarker: View {
    let delta: Double
    var body: some View {
        Text(delta == 0 ? "=" : delta > 0 ? "▲" : "▼")
            .font(Theme.label).foregroundStyle(delta > 0 ? Theme.accent : Theme.secondary)
    }
}

struct ThemeRule: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(height: Theme.ruleWidth) }
}

private struct NativeSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.font(Theme.body).foregroundStyle(Theme.ink).tint(Theme.accent)
            .monospacedDigit()
            .buttonStyle(ThemeButtonStyle())
            .progressViewStyle(NativeProgressStyle())
            .toggleStyle(.switch)
            .menuStyle(.borderlessButton)
    }
}

struct ThemeButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Theme.body)
            .foregroundStyle(primary ? Theme.onAccent : Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(primary ? Theme.accent : Theme.surface,
                        in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
            .opacity(!enabled ? 0.5 : configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: Theme.feedbackDuration), value: configuration.isPressed)
    }
}

struct ThemeMenu<Selection: Hashable>: View {
    let title: String
    @Binding var selection: Selection
    let options: [Selection]
    let label: (Selection) -> String

    var body: some View {
        HStack(spacing: Theme.grid) {
            Text(title)
            Spacer(minLength: Theme.grid)
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(label(option)) { selection = option }
                }
            } label: {
                HStack(spacing: Theme.grid) {
                    Text(label(selection))
                    Image(systemName: "chevron.down").font(Theme.label)
                }.padding(Theme.grid).bauhausPanel()
            }.menuStyle(.borderlessButton)
                .accessibilityLabel(title)
                .accessibilityValue(label(selection))
        }
    }
}

private struct NativeProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: Theme.grid) {
            configuration.label
            if let fraction = configuration.fractionCompleted {
                GeometryReader { proxy in
                    Capsule().fill(Theme.hairline)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Theme.accent).frame(width: proxy.size.width * min(1, max(0, fraction)))
                        }
                }.frame(height: Theme.grid)
            } else {
                Text("↻").accessibilityHidden(true)
            }
        }
    }
}

extension View {
    func bauhausTheme() -> some View { modifier(NativeSurface()) }
    func bauhausPanel() -> some View { background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius)) }
}
