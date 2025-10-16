import Cocoa

class ApplicationObserver {
    private var callback: (NSRunningApplication) -> Void

    init(callback: @escaping (NSRunningApplication) -> Void) {
        self.callback = callback

        // Observe workspace notifications for active application changes
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func activeApplicationChanged(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            callback(app)
        }
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
