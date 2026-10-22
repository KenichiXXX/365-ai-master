import AppKit
import Combine
import SwiftUI
import UserNotifications

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate, UNUserNotificationCenterDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let store = SnapshotStore(weeklyNotifications: WeeklyNotifications(), oneTimeNotifications: OneTimeRenewalNotifications())
    private var clickMonitor: Any?
    private var subscription: AnyCancellable?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        popover.contentSize = NSSize(width: Theme.width, height: Theme.height)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverRoot(store: store).onExitCommand { [weak self] in
            self?.popover.performClose(nil)
        })
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.imagePosition = .imageOnly
        update(snapshot: nil)
        subscription = store.$snapshot.sink { [weak self] snapshot in self?.update(snapshot: snapshot) }
        store.refreshContent()
        store.startTimer()
        store.refresh()
    }

    func handleActivationURL(_ url: URL) {
        store.handleActivationURL(url)
    }

    private func update(snapshot: Snapshot?) {
        let score = snapshot?.hasEvaluableScores == true ? snapshot?.overall?.score : nil
        let pending = snapshot?.book?.today?.lit == false
        statusItem.button?.image = Self.icon(score: score, todayPending: pending)
        statusItem.button?.setAccessibilityTitle(Self.badgeTitle(snapshot: snapshot))
        statusItem.button?.toolTip = pending ? (store.locale == "zh" ? "今天的一招还没练" : "Today's skill is waiting") : "365 AI Master"
    }

    static func badgeTitle(snapshot: Snapshot?) -> String {
        (snapshot?.overall?.score.map(String.init) ?? "—") + (snapshot?.book?.today?.lit == false ? " •" : "")
    }

    static func icon(score: Int?, todayPending: Bool) -> NSImage {
        let text = score.map(String.init) ?? "—"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold), .foregroundColor: NSColor.black]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let ring: CGFloat = 13
        let width = ring + 4 + ceil(textSize.width) + (todayPending ? 6 : 0)
        let image = NSImage(size: NSSize(width: width, height: 18), flipped: false) { rect in
            let center = NSPoint(x: ring / 2 + 0.5, y: rect.midY)
            let radius = ring / 2 - 1.2
            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = 2
            NSColor.black.withAlphaComponent(0.28).setStroke()
            track.stroke()
            if let score, score > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                              endAngle: 90 - 360 * CGFloat(min(100, score)) / 100, clockwise: true)
                arc.lineWidth = 2
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }
            (text as NSString).draw(at: NSPoint(x: ring + 4, y: rect.midY - textSize.height / 2), withAttributes: attributes)
            if todayPending {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: width - 4, y: rect.midY + 3, width: 4, height: 4)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    func popoverDidClose(_ notification: Notification) {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            if response.notification.request.identifier == WeeklyNotifications.identifier {
                await self.store.refresh()?.value
            }
            if self.store.openReminder(response.notification.request.content.userInfo) { self.showPopover() }
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in self?.popover.performClose(nil) }
            }
        }
    }

    @objc private func checkNow() {
        store.recheck()
        showPopover()
    }

    @objc private func openSettings() {
        store.showSettings = true
        showPopover()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func togglePopover() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.performClose(nil)
            let menu = NSMenu()
            let zh = (store.snapshot?.locale ?? store.locale) == "zh"
            for (title, action) in [(zh ? "重新检查" : "Check again", #selector(checkNow)),
                                    (zh ? "设置…" : "Settings…", #selector(openSettings)),
                                    (zh ? "退出" : "Quit", #selector(quit))] {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.target = self
                menu.addItem(item)
            }
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        if popover.isShown { popover.performClose(nil) }
        else {
            store.recordLocalEvent(.foregroundOpen)
            store.refreshContent()
            store.refresh()
            showPopover()
        }
    }
}
