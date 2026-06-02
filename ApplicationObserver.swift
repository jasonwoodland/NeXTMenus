import Cocoa
import ApplicationServices

class ApplicationObserver {
    private var callback: (NSRunningApplication) -> Void
    private var focusedWindowObserver: AXObserver?
    private var observedFocusedWindowPid: pid_t?
    private var observedFocusedWindow: AXUIElement?

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
        guard app.processIdentifier != observedFocusedWindowPid else {
            updateFocusedWindowMovementObservation(for: app)
            return
        }
        stopObservingFocusedWindowChanges()

        var observer: AXObserver?
        let createResult = AXObserverCreate(app.processIdentifier, { _, _, notification, refcon in
            guard let refcon = refcon else { return }
            let observer = Unmanaged<ApplicationObserver>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async {
                guard let app = NSWorkspace.shared.frontmostApplication,
                      app.processIdentifier == observer.observedFocusedWindowPid else { return }
                if notification as String == kAXFocusedWindowChangedNotification {
                    observer.updateFocusedWindowMovementObservation(for: app)
                }
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
        updateFocusedWindowMovementObservation(for: app)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func updateFocusedWindowMovementObservation(for app: NSRunningApplication) {
        guard let observer = focusedWindowObserver,
              app.processIdentifier == observedFocusedWindowPid else { return }

        if let window = observedFocusedWindow {
            AXObserverRemoveNotification(observer, window, kAXMovedNotification as CFString)
            AXObserverRemoveNotification(observer, window, kAXResizedNotification as CFString)
        }
        observedFocusedWindow = nil

        guard let window = focusedWindow(for: app) else { return }
        AXObserverAddNotification(
            observer,
            window,
            kAXMovedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )
        AXObserverAddNotification(
            observer,
            window,
            kAXResizedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )
        observedFocusedWindow = window
    }

    private func focusedWindow(for app: NSRunningApplication) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindowRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef)
        guard result == .success, let focused = focusedWindowRef else { return nil }
        return (focused as! AXUIElement)
    }

    private func stopObservingFocusedWindowChanges() {
        if let observer = focusedWindowObserver {
            if let window = observedFocusedWindow {
                AXObserverRemoveNotification(observer, window, kAXMovedNotification as CFString)
                AXObserverRemoveNotification(observer, window, kAXResizedNotification as CFString)
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        focusedWindowObserver = nil
        observedFocusedWindowPid = nil
        observedFocusedWindow = nil
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        stopObservingFocusedWindowChanges()
    }
}
