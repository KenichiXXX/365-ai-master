import Foundation

/// Bound older downloaded copy as well as the rewritten bundled content.
enum ActionCopy {
    static func line(_ text: String, locale: String, hanLimit: Int = 18, englishLimit: Int = 40) -> String {
        let limit = locale == "zh" ? hanLimit : englishLimit
        var count = 0
        var prefix = ""
        for character in text {
            let units = locale == "zh"
                ? character.unicodeScalars.filter { (0x3400...0x9fff).contains(Int($0.value)) }.count : 1
            if count + units > limit {
                if locale != "zh", !prefix.isEmpty { prefix.removeLast() }
                if let boundary = prefix.lastIndex(where: { "，。；、,; ".contains($0) }) {
                    prefix = String(prefix[..<boundary])
                }
                return prefix.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
            }
            count += units
            prefix.append(character)
        }
        return text
    }

    static func benefit(_ text: String, locale: String) -> String {
        (locale == "zh" ? "能帮你：" : "Helps you: ")
            + line(text, locale: locale, hanLimit: 12, englishLimit: 29)
    }
}
