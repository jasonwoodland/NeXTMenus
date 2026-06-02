import Cocoa
import ApplicationServices

class ApplicationObserver {
    private var callback: (NSRunningApplication) -> Void
    private var focusedWindowObserver: AXObserver?
    private var observedFocusedWindowPid: pid_t?

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
            observeFocusedWindowChanges(for: app)
            callback(app)
        }
    }

    func observeFocusedWindowChanges(for app: NSRunningApplication) {
        guard app.processIdentifier != observedFocusedWindowPid else { return }
        stopObservingFocusedWindowChanges()

        var observer: AXObserver?
        let createResult = AXObserverCreate(app.processIdentifier, { _, _, _, refcon in
            guard let refcon = refcon else { return }
            let observer = Unmanaged<ApplicationObserver>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async {
                guard let app = NSWorkspace.shared.frontmostApplication,
                      app.processIdentifier == observer.observedFocusedWindowPid else { return }
                observer.callback(app)
            }
        }, &observer)
        guard createResult == .success, let observer = observer else { return }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let addResult = AXObserverAddNotification(
            observer,
            appElement,
            kAXFocusedWindowChangedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )
        guard addResult == .success else { return }

        focusedWindowObserver = observer
        observedFocusedWindowPid = app.processIdentifier
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func stopObservingFocusedWindowChanges() {
        if let observer = focusedWindowObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        focusedWindowObserver = nil
        observedFocusedWindowPid = nil
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        stopObservingFocusedWindowChanges()
    }
}
