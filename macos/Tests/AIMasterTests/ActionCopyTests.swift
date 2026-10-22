import XCTest
@testable import AIMaster

final class ActionCopyTests: XCTestCase {
    func testShortCopyIsUnchanged() {
        XCTAssertEqual(ActionCopy.line("Keep one task per chat", locale: "en"), "Keep one task per chat")
        XCTAssertEqual(ActionCopy.benefit("让 AI 记住重点", locale: "zh"), "能帮你：让 AI 记住重点")
    }

    func testLongEnglishCopyIncludesEllipsisWithinBudget() {
        let unbroken = String(repeating: "a", count: 80)
        XCTAssertLessThanOrEqual(ActionCopy.line(unbroken, locale: "en").count, 40)
        XCTAssertLessThanOrEqual(ActionCopy.benefit(unbroken, locale: "en").count, 40)
        XCTAssertTrue(ActionCopy.line(unbroken, locale: "en").hasSuffix("…"))
    }

    func testChineseBenefitEndsAtPhraseBoundary() {
        XCTAssertEqual(ActionCopy.benefit("让 AI 记住重点，减少重复说明并检查结果", locale: "zh"),
                       "能帮你：让 AI 记住重点…")
    }
}
