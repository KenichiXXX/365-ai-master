import SwiftUI
import AppKit

enum Theme {
    static let width: CGFloat = 400
    static let height: CGFloat = 680
    static let page: CGFloat = 16
    static let gap: CGFloat = 12
    static let cardPadding: CGFloat = 14
    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 10
    static let motion = Animation.spring(response: 0.32, dampingFraction: 0.86)

    static let canvas = adaptive(light: 0xF7F5F0, dark: 0x0F131A)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x181D26)
    static let inset = adaptive(light: 0xF0EDE6, dark: 0x222834)
    static let ink = adaptive(light: 0x1B1916, dark: 0xF2EEE6)
    static let secondary = adaptive(light: 0x6E695F, dark: 0xA8A397)
    static let tertiary = adaptive(light: 0xA29C91, dark: 0x6F6B63)
    static let hairline = adaptive(light: 0x1B1916, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.09)
    static let separator = adaptive(light: 0x1B1916, dark: 0xFFFFFF, lightAlpha: 0.06, darkAlpha: 0.07)

    static let gold = adaptive(light: 0xD9A12E, dark: 0xF0BE5A)
    static let goldText = adaptive(light: 0x8A5F0E, dark: 0xF0BE5A)
    static let goldSoft = adaptive(light: 0xFBF1DC, dark: 0xF0BE5A, darkAlpha: 0.10)
    static let onGold = color(0x1B1305)

    static let good = adaptive(light: 0x2E9C84, dark: 0x4FC7A9)
    static let goodText = adaptive(light: 0x1F6E5D, dark: 0x6FD9BD)
    static let goodSoft = adaptive(light: 0xDDF2EC, dark: 0x4FC7A9, darkAlpha: 0.15)
    static let low = adaptive(light: 0xE0674A, dark: 0xF08A6A)
    static let lowText = adaptive(light: 0xB4432A, dark: 0xF4A086)
    static let lowSoft = adaptive(light: 0xFDE7E1, dark: 0xF08A6A, darkAlpha: 0.15)

    static let score = Font.system(size: 44, weight: .semibold, design: .rounded)
    static let title = Font.system(size: 20, weight: .semibold)
    static let headline = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyStrong = Font.system(size: 13, weight: .semibold)
    static let caption = Font.system(size: 11)
    static let captionStrong = Font.system(size: 11, weight: .semibold)
    static func number(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
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
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(stroke, lineWidth: 0.5))
    }

    func appStyle() -> some View {
        self.font(Theme.body)
            .foregroundStyle(Theme.ink)
            .tint(Theme.gold)
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tone: Tone = .gold
    var expand = true
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.bodyStrong)
            .foregroundStyle(tone == .gold ? Theme.onGold : Color.white)
            .padding(.horizontal, 14)
            .frame(maxWidth: expand ? .infinity : nil, minHeight: 34)
            .background(tone.fill.opacity(configuration.isPressed ? 0.8 : 1),
                        in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var expand = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.bodyStrong)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .frame(maxWidth: expand ? .infinity : nil, minHeight: 34)
            .background(Theme.inset.opacity(configuration.isPressed ? 0.6 : 1),
                        in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

struct LinkButtonStyle: ButtonStyle {
    var color: Color = Theme.goldText
    var font: Font = Theme.bodyStrong
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(color.opacity(configuration.isPressed ? 0.6 : 1))
            .contentShape(Rectangle())
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.secondary)
            .frame(width: 28, height: 28)
            .background(Theme.inset.opacity(configuration.isPressed ? 1 : 0),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
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
        .background(tone.soft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                    .background(Theme.goldSoft, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
                .fill(LinearGradient(colors: [Theme.color(0xEDBA52), Theme.color(0xB98419)],
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
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.goldText)
                .frame(width: 17, height: 17)
                .background(fill, in: Circle())
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text(text).font(Theme.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}
