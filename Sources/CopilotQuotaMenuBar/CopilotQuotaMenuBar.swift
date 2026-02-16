import AppKit
import Foundation

@main
final class CopilotQuotaMenuBarApp: NSObject, NSApplicationDelegate {
    private var statusMenuController: StatusMenuController?

    @MainActor
    static func main() {
        // Prevent duplicate menubar icons when launched via LaunchAgent + manual run.
        guard SingleInstanceLock.tryAcquire() else { return }

        let app = NSApplication.shared
        let delegate = CopilotQuotaMenuBarApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusMenuController()
        self.statusMenuController = controller
        controller.start()
    }
}
