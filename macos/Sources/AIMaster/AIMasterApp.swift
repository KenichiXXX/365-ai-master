import SwiftUI
import AppKit

@main
struct AIMasterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController?

    func application(_ application: NSApplication, open urls: [URL]) {
        if controller == nil { controller = StatusItemController() }
        for url in urls { controller?.handleActivationURL(url) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if controller == nil { controller = StatusItemController() }
    }
}
