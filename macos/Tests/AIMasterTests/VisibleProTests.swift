import XCTest
import SwiftUI
@testable import AIMaster

@MainActor
final class VisibleProTests: XCTestCase {
    // Inspect declared Text and Button labels without launching an app or opening URLs.
    private func labels(_ value: Any) -> [String] {
        if let options = value as? PurchaseOptionsView { return labels(options.body) }
        if let trial = value as? ProTrialSection { return labels(trial.body) }
        if let lock = value as? ProLockLabel { return labels(lock.body) }
        if String(describing: type(of: value)).hasPrefix("DisclosureGroup<") { return [] }
        if value is Text { return [String(reflecting: value)] }
        return Mirror(reflecting: value).children.flatMap { labels($0.value) }
    }

    func testSheetLeadsWithProTitlePriceAndHonestPaymentStatus() {
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        for zh in [true, false] {
            let text = labels(ProSettingsSection(store: store, zh: zh).body).joined(separator: "\n")
            XCTAssertTrue(text.contains("365 AI MASTER PRO"), text)
            XCTAssertTrue(text.contains(zh ? "$12 / 年 · 创始价" : "$12 / year · Founding price"), text)
            XCTAssertTrue(text.contains(zh ? "付款通道开通中" : "Payments coming soon"), text)
        }
    }

    func testEligibleTrialHasExplicitFourteenDayAction() {
        var data: Data?
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
            proTrial: ProTrial(read: { data }, write: { data = $0 }))
        for zh in [true, false] {
            let text = labels(ProTrialSection(store: store, zh: zh).body).joined(separator: "\n")
            XCTAssertTrue(text.contains(zh ? "开始 14 天免费试用" : "Start 14-day free trial"), text)
            XCTAssertTrue(text.contains(zh ? "不自动扣款" : "no automatic charge"), text)
        }
    }
    func testFourBenefitsAndNoPurchaseActionWhenCheckoutIsUnavailable() {
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        XCTAssertNil(store.purchaseConfiguration.checkout(source: nil))
        for zh in [true, false] {
            let text = labels(ProSettingsSection(store: store, zh: zh).body)
            XCTAssertEqual(text.filter { $0.contains("▲") }.count, 4)
            for benefit in zh ? ["成长曲线", "每周复盘", "Top 20 完整榜单", "四维全球排名"]
                              : ["Growth curve", "Weekly review", "Full Top 20 rankings", "Global rankings in four dimensions"] {
                XCTAssertTrue(text.contains { $0.contains(benefit) }, benefit)
            }
            XCTAssertFalse(text.contains { $0.contains("\"Buy\"") || $0.contains("\"购买\"") })
            XCTAssertTrue(text.contains { $0.contains(zh ? "输入激活码" : "Enter activation key") })
        }
    }

    func testTrialActionDisappearsAfterStartAndExpiry() {
        var data: Data?
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
            proTrial: ProTrial(clock: { now }, read: { data }, write: { data = $0 }))
        store.startProTrial()
        XCTAssertTrue(store.isPro)
        for expired in [false, true] {
            if expired { now += 14 * 86400; store.resumeEntitlement() }
            for zh in [true, false] {
                let text = labels(ProSettingsSection(store: store, zh: zh).body).joined(separator: "\n")
                XCTAssertFalse(text.contains(zh ? "开始 14 天免费试用" : "Start 14-day free trial"))
            }
        }
        XCTAssertFalse(store.isPro)
    }

    private func lockCount(_ value: Any) -> Int {
        if value is ProLockLabel { return 1 }
        return Mirror(reflecting: value).children.reduce(0) { $0 + lockCount($1.value) }
    }

    func testDetailLocksAppearOnlyForGatedFeatures() throws {
        let dimension = try XCTUnwrap(EngineRunner.decode(Data(#"{"schema":3,"dimensions":[{"key":"routing","label":"Routing","score":80}]}"#.utf8), status: 0).snapshot.dimensions?.first)
        let card = SkillCard(id: "locked", title: "Skill", why: "Why", prompt: "Prompt", level: 1, lit: false, how: nil)
        var data: Data?
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
            proTrial: ProTrial(read: { data }, write: { data = $0 }))
        for pro in [false, true] {
            if pro { store.startProTrial() }
            for locale in ["zh", "en"] {
                let detail = DimensionDetail(dimension: dimension, growth: nil, features: store.features,
                    locale: locale, store: store, back: {})
                XCTAssertEqual(lockCount(detail.body), pro ? 0 : 2)
                XCTAssertEqual(lockCount(SkillCardDetails(card: card, todayID: nil, store: store, locale: locale).body), pro ? 0 : 1)
            }
        }
    }

    func testProSheetRendersInBothLanguagesAndAppearances() throws {
        var data: Data?
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
            proTrial: ProTrial(read: { data }, write: { data = $0 }))
        for pro in [false, true] {
            if pro { store.startProTrial() }
            for zh in [true, false] {
                for scheme in [ColorScheme.light, .dark] {
                    let renderer = ImageRenderer(content: ProSettingsSection(store: store, zh: zh)
                        .padding(Theme.grid * 2).frame(width: 380)
                        .environment(\.colorScheme, scheme))
                    let image = try XCTUnwrap(renderer.nsImage)
                    XCTAssertEqual(image.size.width, 380)
                    XCTAssertLessThan(image.size.height, 620, "Pro offer should fit the header-entry sheet")
                }
            }
        }
    }

}
