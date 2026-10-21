import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let store = SnapshotStore()
    private var subscription: AnyCancellable?

    override init() {
        super.init()
        popover.contentSize = NSSize(width: 360, height: 560)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store))
        statusItem.button?.title = Self.badgeTitle(snapshot: nil)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        subscription = store.$snapshot.sink { [weak self] snapshot in
            self?.statusItem.button?.title = Self.badgeTitle(snapshot: snapshot)
        }
        store.startTimer()
        store.refresh()
    }

    static func badgeTitle(snapshot: Snapshot?) -> String {
        guard let village = snapshot?.village else { return "○" }
        guard let current = village.current else { return "✓" }
        let numbers = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨"]
        guard let index = village.quests.firstIndex(where: { $0.key == current }), index < numbers.count else { return "○" }
        let tip = snapshot?.todayTip
        let unmet = tip?.source.kind == "quest" && village.quests.contains {
            $0.key == tip?.source.ref && $0.status != "passed"
        }
        return numbers[index] + (unmet ? " •" : "")
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
