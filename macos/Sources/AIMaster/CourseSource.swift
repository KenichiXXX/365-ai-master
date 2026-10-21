import Foundation

struct CourseSource: Equatable {
    let code: String
    let practiceID: String
    let title: [String: String]
    private init(code: String, practiceID: String, title: [String: String]) {
        self.code = code
        self.practiceID = practiceID
        self.title = title
    }

    static func catalogue(_ data: Data, practiceIDs: Set<String>) -> [CourseSource] {
        guard data.count <= 2_000_000,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = object["course_sources"] as? [[String: Any]], entries.count <= 100 else { return [] }
        var result: [CourseSource] = []
        var seen: Set<String> = []
        for entry in entries {
            guard Set(entry.keys) == ["code", "practice_id", "title"],
                  let code = entry["code"] as? String, valid(code), seen.insert(code).inserted,
                  let id = entry["practice_id"] as? String, practiceIDs.contains(id),
                  let title = entry["title"] as? [String: String], Set(title.keys) == ["zh", "en"],
                  title.values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 120 }) else { return [] }
            result.append(.init(code: code, practiceID: id, title: title))
        }
        return result
    }

    private static func valid(_ code: String) -> Bool {
        (1...32).contains(code.utf8.count) && code.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }

    static func match(_ code: String, in catalogue: [CourseSource]) -> CourseSource? {
        guard valid(code) else { return nil }
        return catalogue.first { $0.code == code }
    }
}
