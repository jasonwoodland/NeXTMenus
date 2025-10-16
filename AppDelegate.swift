import Cocoa
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    var menuWindowControllers: [pid_t: MenuWindowController] = [:]
    var applicationObserver: ApplicationObserver?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the app from the Dock
        NSApp.setActivationPolicy(.accessory)

        // Prevent the app from activating when windows are clicked
        NSApp.activate(ignoringOtherApps: false)

        // Request accessibility permissions
        requestAccessibilityPermissions()

        // Start observing active application changes
        applicationObserver = ApplicationObserver { [weak self] runningApp in
            self?.handleActiveApplicationChange(runningApp)
        }

        // Handle initial active application
        if let activeApp = NSWorkspace.shared.frontmostApplication {
            handleActiveApplicationChange(activeApp)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Don't activate when reopened
        return false
    }

    private func requestAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)

        if !accessibilityEnabled {
            print("Please grant accessibility permissions in System Preferences > Security & Privacy > Privacy > Accessibility")
        }
    }

    private func handleActiveApplicationChange(_ app: NSRunningApplication) {
        // Skip our own app
        if app.processIdentifier == NSRunningApplication.current.processIdentifier {
            return
        }

        let pid = app.processIdentifier

        // Get or create window controller for this app
        let menuWindowController: MenuWindowController
        if let existing = menuWindowControllers[pid] {
            menuWindowController = existing
        } else {
            // Extract menu items from the application
            let (appMenuItem, menuItems) = MenuExtractor.extractMenuItems(from: app)

            // Create new window controller for this app
            menuWindowController = MenuWindowController(
                appName: app.localizedName ?? "Unknown",
                appMenuItem: appMenuItem,
                menuItems: menuItems,
                targetApp: app
            )
            menuWindowControllers[pid] = menuWindowController
        }

        // Hide all other windows
        for (otherPid, controller) in menuWindowControllers {
            if otherPid != pid {
                controller.hideWindow()
            }
        }

        // Show this app's window
        menuWindowController.showWindow()
    }
}
