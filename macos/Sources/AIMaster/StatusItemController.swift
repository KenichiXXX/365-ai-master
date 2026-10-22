import AppKit
import Combine
import SwiftUI
import UserNotifications

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate, UNUserNotificationCenterDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let store = SnapshotStore(weeklyNotifications: WeeklyNotifications())
    private var clickMonitor: Any?
    private var subscription: AnyCancellable?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        popover.contentSize = NSSize(width: 440, height: 720)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store).onExitCommand { [weak self] in
            self?.popover.performClose(nil)
        })
        statusItem.button?.title = Self.badgeTitle(snapshot: nil)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        subscription = store.$snapshot.sink { [weak self] snapshot in
            self?.statusItem.button?.title = Self.badgeTitle(snapshot: snapshot)
        }
        store.refreshContent()
        store.startTimer()
        store.refresh()
    }

    func handleActivationURL(_ url: URL) {
        store.handleActivationURL(url)
    }

    static func badgeTitle(snapshot: Snapshot?) -> String {
        (snapshot?.overall?.score.map(String.init) ?? "—") + (snapshot?.book?.today?.lit == false ? " •" : "")
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
                if self.store.openReminder(response.notification.request.content.userInfo) { self.showPopover() }
            }
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
            for (title, action) in [(zh ? "立即体检" : "Check now", #selector(checkNow)),
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
