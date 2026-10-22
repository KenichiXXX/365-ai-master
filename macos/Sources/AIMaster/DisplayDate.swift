import Foundation

// Parse transport dates at the UI boundary; never fall back to an ISO string.
enum DisplayDate {
    static func short(_ value: String, locale: String, time: Bool = true, year: Bool = false,
                      timeZone: TimeZone = .current) -> String {
        let iso = ISO8601DateFormatter()
        var date = iso.date(from: value)
        if date == nil {
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = iso.date(from: value)
        }
        let dateOnly = value.count == 10
        if dateOnly {
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.timeZone = timeZone
            parser.dateFormat = "yyyy-MM-dd"
            parser.isLenient = false
            date = parser.date(from: value)
        }
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale.hasPrefix("zh") ? "zh_CN" : "en_US")
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate((year ? "y" : "") + (time && !dateOnly ? "MMMdjmm" : "MMMd"))
        return formatter.string(from: date)
    }
}
