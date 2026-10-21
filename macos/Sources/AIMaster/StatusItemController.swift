import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let store = SnapshotStore()
    private var clickMonitor: Any?
    private var subscription: AnyCancellable?

    override init() {
        super.init()
        popover.contentSize = NSSize(width: 440, height: 720)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store).onExitCommand { [weak self] in
            self?.popover.performClose(nil)
        })
        statusItem.button?.title = Self.badgeTitle(snapshot: nil)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        subscription = store.$snapshot.sink { [weak self] snapshot in
            self?.statusItem.button?.title = Self.badgeTitle(snapshot: snapshot)
        }
        store.refreshContent()
        store.startTimer()
        store.refresh()
    }

    static func badgeTitle(snapshot: Snapshot?) -> String {
        guard let village = snapshot?.village else { return "○" }
        guard let current = village.current else { return "✓" + (snapshot?.book?.today?.lit == false ? " •" : "") }
        let numbers = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨"]
        guard let index = village.quests.firstIndex(where: { $0.key == current }), index < numbers.count else { return "○" }
        return numbers[index] + (snapshot?.book?.today?.lit == false ? " •" : "")
    }

    func popoverDidClose(_ notification: Notification) {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            store.refreshContent()
            store.refresh()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            if clickMonitor == nil {
                clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                    Task { @MainActor in self?.popover.performClose(nil) }
                }
            }
        }
    }
}
