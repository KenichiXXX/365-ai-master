import Foundation

struct PracticeCalendarData: Decodable {
    let days: [PracticeCalendarDay]
    let labels: [String: String]
}

struct PracticeCalendarDay: Decodable, Identifiable {
    let date: String
    let state: String
    var id: String { date }
}
