import SwiftUI

/// The three-size, eight-point Bauhaus vocabulary shared by every app surface.
enum Theme {
    static let grid: CGFloat = 8
    static let cornerRadius: CGFloat = 0
    static let ruleWidth: CGFloat = 1
    static let fixedPaper = color(0xF4F0E6)
    static let fixedInk = color(0x111111)
    static let red = color(0xD7282F)
    static let blue = color(0x1F4E9E)
    static let yellow = color(0xF2C230)

    static func background(for scheme: ColorScheme) -> Color { scheme == .dark ? fixedInk : fixedPaper }
    static func foreground(for scheme: ColorScheme) -> Color { scheme == .dark ? fixedPaper : fixedInk }
    static let paper = adaptive(light: 0xF4F0E6, dark: 0x111111)
    static let ink = adaptive(light: 0x111111, dark: 0xF4F0E6)
    static let secondary = ink.opacity(0.6)

    static let body = Font.custom("PingFangSC-Regular", size: 16)
    static let title = Font.custom("PingFangSC-Semibold", size: 16)
    static let label = Font.system(size: 10, weight: .semibold)
    static let score = Font.system(size: 48, weight: .heavy, design: .rounded)
    static func proTitle(isPro: Bool) -> String { isPro ? "PRO ✓" : "PRO" }

    private static func color(_ hex: Int) -> Color { Color(nsColor: nsColor(hex)) }
    private static func nsColor(_ hex: Int) -> NSColor {
        NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1)
    }
    private static func adaptive(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            nsColor(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
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

    var body: some View {
        HStack(spacing: Theme.grid * 3) {
            ForEach(MasterTab.allCases, id: \.rawValue) { tab in
                Button { selection = tab.rawValue } label: {
                    Text(tab.title(locale: locale)).font(Theme.title)
                        .foregroundStyle(selection == tab.rawValue ? Theme.ink : Theme.secondary)
                        .padding(.vertical, Theme.grid)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(selection == tab.rawValue ? Theme.ink : .clear).frame(height: 2)
                        }
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(selection == tab.rawValue ? .isSelected : [])
                    .accessibilityIdentifier("tab-\(tab.rawValue)")
            }
            Spacer(minLength: 0)
        }
    }
}

struct ThemeLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title.uppercased()).font(Theme.label).tracking(2).foregroundStyle(Theme.ink)
    }
}

/// Direction is encoded by geometry; accompanying text keeps the high-contrast ink.
struct TrendMarker: View {
    let delta: Double
    var body: some View {
        if delta == 0 {
            Text("=").font(Theme.label).foregroundStyle(Theme.secondary)
        } else {
            Triangle().fill(delta > 0 ? Theme.red : Theme.secondary)
                .rotationEffect(.degrees(delta > 0 ? 0 : 180))
                .frame(width: Theme.grid, height: Theme.grid)
                .accessibilityLabel(delta > 0 ? "▲" : "▼")
        }
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.closeSubpath()
            }
        }
    }
}

struct ThemeRule: View {
    var body: some View { Rectangle().fill(Theme.ink).frame(height: Theme.ruleWidth) }
}

private struct BauhausSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.font(Theme.body).foregroundStyle(Theme.foreground(for: scheme))
            .tint(Theme.foreground(for: scheme))
            .buttonStyle(BauhausButtonStyle())
            .progressViewStyle(BauhausProgressStyle())
            .toggleStyle(BauhausToggleStyle())
            .menuStyle(.borderlessButton)
            .background(Theme.background(for: scheme))
    }
}

private struct BauhausButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Theme.body).foregroundStyle(enabled ? Theme.ink : Theme.secondary)
            .padding(Theme.grid)
            .background(configuration.isPressed ? Theme.ink.opacity(0.1) : Theme.paper)
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: Theme.ruleWidth))
    }
}

private struct BauhausToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: Theme.grid) {
                Rectangle().fill(configuration.isOn ? Theme.ink : Theme.paper)
                    .frame(width: Theme.grid * 2, height: Theme.grid * 2)
                    .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: Theme.ruleWidth))
                    .overlay {
                        if configuration.isOn { Image(systemName: "checkmark").font(Theme.label).foregroundStyle(Theme.paper) }
                    }
                configuration.label
            }.foregroundStyle(Theme.ink)
        }.buttonStyle(.plain)
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.checkbox)
            }
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

private struct BauhausProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: Theme.grid) {
            configuration.label
            if let fraction = configuration.fractionCompleted {
                GeometryReader { proxy in
                    Rectangle().fill(Theme.paper)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Theme.blue).frame(width: proxy.size.width * min(1, max(0, fraction)))
                        }
                        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: Theme.ruleWidth))
                }.frame(height: Theme.grid)
            } else {
                Text("↻").accessibilityHidden(true)
            }
        }
    }
}

extension View {
    func bauhausTheme() -> some View { modifier(BauhausSurface()) }
    func bauhausPanel() -> some View {
        background(Theme.paper).overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: Theme.ruleWidth))
    }
}
