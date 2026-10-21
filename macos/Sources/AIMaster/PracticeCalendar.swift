import SwiftUI

struct PracticeCalendarData: Decodable {
    let days: [PracticeCalendarDay]
    let labels: [String: String]
}

struct PracticeCalendarDay: Decodable, Identifiable {
    let date: String
    let state: String
    var id: String { date }
    func accessibilityLabel(labels: [String: String]) -> String {
        "\(date), \(labels[state] ?? labels["unavailable"] ?? state)"
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
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(data.labels["title"] ?? "").font(.headline)
            if let first = data.days.first, let last = data.days.last {
                Text("\(first.date) – \(last.date)").font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(data.days) { day in
                    VStack(spacing: 3) {
                        Image(systemName: day.symbol)
                        Text(String(day.date.suffix(2))).font(.caption2)
                    }.frame(maxWidth: .infinity)
                        .foregroundStyle(day.state == "observed" ? Color.accentColor : Color.secondary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(day.accessibilityLabel(labels: data.labels))
                        .help(day.accessibilityLabel(labels: data.labels))
                }
            }
            Text(["observed", "self_reported", "usage_only", "unavailable"].compactMap { data.labels[$0] }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            Text(data.labels["rest"] ?? "").font(.caption).foregroundStyle(.secondary)
        }
    }
}
