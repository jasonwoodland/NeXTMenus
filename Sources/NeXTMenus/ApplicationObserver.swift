import Cocoa
import ApplicationServices

class ApplicationObserver {
    private var callback: (NSRunningApplication) -> Void
    private var focusedWindowObserver: AXObserver?
    private var observedFocusedWindowPid: pid_t?
    private var observedAppElement: AXUIElement?
    private var observedFocusedWindow: AXUIElement?
    private var observedWindows: [AXUIElement] = []

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
            updateWindowStateObservation(for: app)
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
                let notificationName = notification as String
                if notificationName == kAXFocusedWindowChangedNotification {
                    observer.updateFocusedWindowMovementObservation(for: app)
                }
                if observer.shouldRefreshObservedWindowSet(for: notificationName) {
                    observer.updateWindowStateObservation(for: app)
                }
                observer.callback(app)
            }
        }, &observer)
        guard createResult == .success, let observer = observer else { return }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let addFocusedResult = AXObserverAddNotification(
            observer,
            appElement,
            kAXFocusedWindowChangedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )
        guard addFocusedResult == .success else { return }

        AXObserverAddNotification(
            observer,
            appElement,
            kAXWindowCreatedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )

        focusedWindowObserver = observer
        observedFocusedWindowPid = app.processIdentifier
        observedAppElement = appElement
        updateFocusedWindowMovementObservation(for: app)
        updateWindowStateObservation(for: app)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func shouldRefreshObservedWindowSet(for notificationName: String) -> Bool {
        notificationName == kAXFocusedWindowChangedNotification as String
            || notificationName == kAXWindowCreatedNotification as String
            || notificationName == kAXWindowMiniaturizedNotification as String
            || notificationName == kAXWindowDeminiaturizedNotification as String
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

    private func updateWindowStateObservation(for app: NSRunningApplication) {
        guard let observer = focusedWindowObserver,
              app.processIdentifier == observedFocusedWindowPid else { return }

        removeWindowStateNotifications(from: observedWindows, observer: observer)
        observedWindows = windows(for: app)
        for window in observedWindows {
            AXObserverAddNotification(
                observer,
                window,
                kAXWindowMiniaturizedNotification as CFString,
                Unmanaged.passUnretained(self).toOpaque()
            )
            AXObserverAddNotification(
                observer,
                window,
                kAXWindowDeminiaturizedNotification as CFString,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
    }

    private func removeWindowStateNotifications(from windows: [AXUIElement], observer: AXObserver) {
        for window in windows {
            AXObserverRemoveNotification(observer, window, kAXWindowMiniaturizedNotification as CFString)
            AXObserverRemoveNotification(observer, window, kAXWindowDeminiaturizedNotification as CFString)
        }
    }

    private func focusedWindow(for app: NSRunningApplication) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindowRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef)
        guard result == .success, let focused = focusedWindowRef else { return nil }
        return (focused as! AXUIElement)
    }

    private func windows(for app: NSRunningApplication) -> [AXUIElement] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )
        guard result == .success, let windows = windowsValue as? [AXUIElement] else { return [] }
        return windows
    }

    private func stopObservingFocusedWindowChanges() {
        if let observer = focusedWindowObserver {
            if let appElement = observedAppElement {
                AXObserverRemoveNotification(
                    observer,
                    appElement,
                    kAXFocusedWindowChangedNotification as CFString
                )
                AXObserverRemoveNotification(
                    observer,
                    appElement,
                    kAXWindowCreatedNotification as CFString
                )
            }
            if let window = observedFocusedWindow {
                AXObserverRemoveNotification(observer, window, kAXMovedNotification as CFString)
                AXObserverRemoveNotification(observer, window, kAXResizedNotification as CFString)
            }
            removeWindowStateNotifications(from: observedWindows, observer: observer)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        focusedWindowObserver = nil
        observedFocusedWindowPid = nil
        observedAppElement = nil
        observedFocusedWindow = nil
        observedWindows = []
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        stopObservingFocusedWindowChanges()
    }
}
