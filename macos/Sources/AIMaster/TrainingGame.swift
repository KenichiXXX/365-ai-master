import Foundation

struct TrainingGame: Decodable {
    let xp: Int
    let level: Int
    let levelXp: Int
    let nextLevelXp: Int
    let levelTitle: String
    let today: DailyGameProgress
    let shields: Int
    let streak: Int
    let bestStreak: Int
    let month: String
    let firstWeekday: Int
    let calendar: [CheckinDay]
    let weekly: GameChallenge
    let weeklyBadges: [String]
}

struct DailyGameProgress: Decodable {
    let checkin: Bool
    let cardRead: Bool
    let practice: Bool
    let completed: Int
    let chestTip: String?
}

struct CheckinDay: Decodable, Identifiable {
    var id: String { date }
    let date: String
    let state: String
}

struct GameChallenge: Decodable {
    let week: String
    let kind: String
    let title: String
    let have: Int
    let need: Int
    let earned: Bool
}
