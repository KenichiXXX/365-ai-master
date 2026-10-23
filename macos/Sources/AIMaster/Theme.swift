import SwiftUI
import AppKit

enum Theme {
    static let width: CGFloat = 400
    static let height: CGFloat = 680
    static let page: CGFloat = 16
    static let gap: CGFloat = 12
    static let cardPadding: CGFloat = 14
    static let cardRadius: CGFloat = 8
    static let controlRadius: CGFloat = 8
    static let motion = Animation.spring(response: 0.32, dampingFraction: 0.86)

    static let canvas = adaptive(light: 0xF7F7FB, dark: 0x17181E)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x202129)
    static let inset = adaptive(light: 0xF0EFF6, dark: 0x2C2D38)
    static let ink = adaptive(light: 0x252532, dark: 0xF4F4F8)
    static let secondary = adaptive(light: 0x626575, dark: 0xA6A7B7)
    static let tertiary = adaptive(light: 0x626575, dark: 0xA6A7B7)
    static let hairline = adaptive(light: 0xE6E5EE, dark: 0x41434F)
    static let separator = adaptive(light: 0xE6E5EE, dark: 0x41434F)

    static let primary = color(0x6754C4)
    static let primaryText = adaptive(light: 0x6754C4, dark: 0xBBAFF3)
    static let primarySoft = adaptive(light: 0xEEEBF8, dark: 0x2E2946)
    static let onPrimary = Color.white
    static let focusRing = adaptive(light: 0x6754C4, dark: 0xBBAFF3)

    // Compatibility names keep every existing page and semantic tone intact.
    static let gold = primary
    static let goldText = primaryText
    static let goldSoft = primarySoft
    static let onGold = onPrimary

    static let good = adaptive(light: 0x22724E, dark: 0x7DCEA7)
    static let goodText = adaptive(light: 0x22724E, dark: 0x7DCEA7)
    static let goodSoft = adaptive(light: 0xE8F3ED, dark: 0x7DCEA7, darkAlpha: 0.15)
    static let low = adaptive(light: 0xB53650, dark: 0xF29AAA)
    static let lowText = adaptive(light: 0xB53650, dark: 0xF29AAA)
    static let lowSoft = adaptive(light: 0xFBEAEE, dark: 0xF29AAA, darkAlpha: 0.15)

    static let score = Font.system(size: 44, weight: .semibold)
    static let title = Font.system(size: 20, weight: .semibold)
    static let headline = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyStrong = Font.system(size: 13, weight: .semibold)
    static let caption = Font.system(size: 11)
    static let captionStrong = Font.system(size: 11, weight: .semibold)
    static func number(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    static func color(_ hex: Int) -> Color { Color(nsColor: nsColor(hex)) }

    static func nsColor(_ hex: Int, alpha: Double = 1) -> NSColor {
        NSColor(srgbRed: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
                blue: Double(hex & 255) / 255, alpha: alpha)
    }

    private static func adaptive(light: Int, dark: Int, lightAlpha: Double = 1, darkAlpha: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return nsColor(isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

enum Tone {
    case gold, good, low, neutral

    var fill: Color {
        switch self {
        case .gold: return Theme.gold
        case .good: return Theme.good
        case .low: return Theme.low
        case .neutral: return Theme.tertiary
        }
    }
    var text: Color {
        switch self {
        case .gold: return Theme.goldText
        case .good: return Theme.goodText
        case .low: return Theme.lowText
        case .neutral: return Theme.secondary
        }
    }
    var soft: Color {
        switch self {
        case .gold: return Theme.goldSoft
        case .good: return Theme.goodSoft
        case .low: return Theme.lowSoft
        case .neutral: return Theme.inset
        }
    }
}

extension View {
    func card(padding: CGFloat = Theme.cardPadding, fill: Color = Theme.surface, stroke: Color = Theme.hairline) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(stroke, lineWidth: 1))
    }

    func appStyle() -> some View {
        self.font(Theme.body)
            .foregroundStyle(Theme.ink)
            .tint(Theme.gold)
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}

// Shared visual states leave Button actions, keyboard shortcuts and native focus routing unchanged.
private struct AtelierControlSurface: ViewModifier {
    let fill: Color
    var pressed = false
    var outlined = false
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(Color.black.opacity(enabled ? (pressed ? 0.16 : hovered ? 0.07 : 0) : 0))
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .strokeBorder(focused && enabled ? Theme.focusRing : outlined ? Theme.hairline : .clear,
                                  lineWidth: focused && enabled ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .opacity(enabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .onHover { hovered = $0 }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tone: Tone = .gold
    var expand = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.bodyStrong)
            .foregroundStyle(tone == .gold ? Theme.onGold : Color.white)
            .padding(.horizontal, 14)
            .frame(maxWidth: expand ? .infinity : nil, minHeight: 40)
            .modifier(AtelierControlSurface(fill: tone.fill, pressed: configuration.isPressed))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var expand = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.bodyStrong)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .frame(maxWidth: expand ? .infinity : nil, minHeight: 40)
            .modifier(AtelierControlSurface(fill: Theme.inset, pressed: configuration.isPressed, outlined: true))
    }
}

struct LinkButtonStyle: ButtonStyle {
    var color: Color = Theme.goldText
    var font: Font = Theme.bodyStrong
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(color)
            .modifier(AtelierControlSurface(fill: .clear, pressed: configuration.isPressed))
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.secondary)
            .frame(width: 28, height: 28)
            .modifier(AtelierControlSurface(fill: .clear, pressed: configuration.isPressed))
    }
}

struct Chip: View {
    let text: String
    var tone: Tone = .neutral
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .bold)) }
            Text(text)
        }
        .font(Theme.captionStrong)
        .foregroundStyle(tone.text)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(tone.soft, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .fixedSize()
    }
}

struct ProgressBar: View {
    let value: Double
    var tone: Tone = .gold
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(Theme.hairline)
                .overlay(alignment: .leading) {
                    Capsule().fill(tone.fill)
                        .frame(width: max(height, proxy.size.width * min(1, max(0, value))))
                        .opacity(value > 0 ? 1 : 0)
                }
        }.frame(height: height)
        .accessibilityHidden(true)
    }
}

struct ScoreRing: View {
    let score: Int?
    var size: CGFloat = 84
    var line: CGFloat = 8
    var tone: Tone = .gold
    var font: Font? = nil
    var fraction: Double? = nil

    var body: some View {
        ZStack {
            Circle().stroke(Theme.hairline, lineWidth: line)
            Circle()
                .trim(from: 0, to: fraction ?? Double(min(100, max(0, score ?? 0))) / 100)
                .stroke(tone.fill, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(score.map(String.init) ?? "—")
                .font(font ?? Theme.number(size * 0.36))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(score.map { "\($0)" } ?? "—")
    }
}

struct SectionHeader: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Theme.captionStrong).foregroundStyle(Theme.secondary)
            Spacer()
            if let detail { Text(detail).font(Theme.caption).foregroundStyle(Theme.tertiary) }
        }.padding(.horizontal, 4)
    }
}

struct NavRow: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var badge: AnyView? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.goldText)
                    .frame(width: 26, height: 26)
                    .background(Theme.goldSoft, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                Text(title).font(Theme.body).foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                if let badge { badge }
                if let detail {
                    Text(detail).font(Theme.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.tertiary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.separator).frame(height: 1) }
}

struct AppMark: View {
    var size: CGFloat = 20
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [Theme.color(0x8573DA), Theme.primary],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().trim(from: 0, to: 0.72)
                .stroke(Color.white, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: size * 0.52, height: size * 0.52)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct ProLock: View {
    var body: some View { Chip(text: "PRO", tone: .gold, icon: "lock.fill") }
}

struct StepRow: View {
    let number: Int
    let text: String
    var fill: Color = Theme.goldSoft

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.goldText)
                .frame(width: 17, height: 17)
                .background(fill, in: Circle())
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text(text).font(Theme.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}
