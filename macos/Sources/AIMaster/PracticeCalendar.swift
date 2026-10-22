import SwiftUI

struct PracticeCalendarData: Decodable {
    let days: [PracticeCalendarDay]
    let labels: [String: String]
}

struct PracticeCalendarDay: Decodable, Identifiable {
    let date: String
    let state: String
    var id: String { date }
    func accessibilityLabel(labels: [String: String], locale: String = "en") -> String {
        "\(DisplayDate.short(date, locale: locale)), \(labels[state] ?? labels["unavailable"] ?? state)"
    }
    var symbol: String {
        switch state {
        case "observed": return "checkmark.circle.fill"
        case "self_reported": return "person.crop.circle"
        case "usage_only": return "circle.lefthalf.filled"
        default: return "questionmark.circle"
        }
    }
}

struct PracticeCalendar: View {
    let data: PracticeCalendarData
    @Environment(\.locale) private var locale
    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text(data.labels["title"] ?? "").font(Theme.title)
                if let first = data.days.first, let last = data.days.last {
                    Text("\(DisplayDate.short(first.date, locale: locale.identifier)) – \(DisplayDate.short(last.date, locale: locale.identifier))").font(Theme.label).foregroundStyle(Theme.secondary)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                    ForEach(data.days) { day in
                        VStack(spacing: Theme.grid) {
                            Image(systemName: day.symbol)
                            Text(String(day.date.suffix(2))).font(Theme.label)
                        }.frame(maxWidth: .infinity)
                            .foregroundStyle(day.state == "observed" ? Theme.ink : Theme.secondary)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(day.accessibilityLabel(labels: data.labels, locale: locale.identifier))
                            .help(day.accessibilityLabel(labels: data.labels, locale: locale.identifier))
                    }
                }
                Text(["observed", "self_reported", "usage_only", "unavailable"].compactMap { data.labels[$0] }.joined(separator: " · "))
                    .font(Theme.label).foregroundStyle(Theme.secondary)
                Text(data.labels["rest"] ?? "").font(Theme.label).foregroundStyle(Theme.secondary)
            }
        }.bauhausTheme()
    }
}
