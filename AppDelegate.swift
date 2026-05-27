import Cocoa
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    var menuWindowControllers: [pid_t: MenuWindowController] = [:]
    var applicationObserver: ApplicationObserver?
    private var visibleMenuPid: pid_t?

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

        // Re-evaluate fullscreen visibility on space changes (entering /
        // exiting fullscreen swaps to a new space).
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        // Drop cached windows for apps that have quit. Otherwise the cache
        // grows for the whole NeXTMenus session, making every app switch walk
        // and hide an ever-larger set of stale controllers.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(applicationTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        // Handle initial active application
        if let activeApp = NSWorkspace.shared.frontmostApplication {
            handleActiveApplicationChange(activeApp)
        }
    }

    @objc private func activeSpaceChanged() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let controller = menuWindowControllers[app.processIdentifier] else { return }
        if MenuExtractor.isFullscreen(app) {
            controller.hideWindow()
        } else {
            controller.showWindow()
        }
    }

    @objc private func applicationTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if let controller = menuWindowControllers.removeValue(forKey: app.processIdentifier) {
            controller.hideWindow()
        }
        if visibleMenuPid == app.processIdentifier {
            visibleMenuPid = nil
        }
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
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
            menuWindowController.resetPosition()

            // Submenus are extracted lazily when opened. Eager recursive
            // extraction presses every submenu in the target app and can spike
            // both this process and WindowServer.

            // A just-launched app's accessibility menu bar can read empty for
            // a moment; retry until it's populated.
            if menuItems.isEmpty {
                retryMenuExtraction(for: app, attempt: 0)
            }
        }

        // Hide only the previously visible menu. Walking every cached app on
        // each activation makes switching slower as the cache grows.
        if let visibleMenuPid, visibleMenuPid != pid,
           let previousController = menuWindowControllers[visibleMenuPid] {
            previousController.hideWindow()
        }

        // Skip showing our menu when the target app is in fullscreen -
        // its own menu bar is hidden, so ours should be too.
        if MenuExtractor.isFullscreen(app) {
            menuWindowController.hideWindow()
            visibleMenuPid = nil
        } else {
            menuWindowController.showWindow()
            visibleMenuPid = pid
        }
    }

    // Re-reads an app's menu bar until it's populated. The accessibility menu
    // bar can be empty briefly right after an app launches.
    private func retryMenuExtraction(for app: NSRunningApplication, attempt: Int) {
        guard attempt < 24, !app.isTerminated else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self = self,
                  let controller = self.menuWindowControllers[app.processIdentifier],
                  !app.isTerminated else { return }

            let (appMenuItem, menuItems) = MenuExtractor.extractMenuItems(from: app)
            if menuItems.isEmpty {
                self.retryMenuExtraction(for: app, attempt: attempt + 1)
            } else {
                controller.applyFullMenu(appMenuItem: appMenuItem, menuItems: menuItems)
            }
        }
    }
}
