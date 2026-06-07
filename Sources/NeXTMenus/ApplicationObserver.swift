import Cocoa
import ApplicationServices

class ApplicationObserver {
    static let appElementNotificationNames = [
        kAXFocusedWindowChangedNotification as String,
        kAXWindowCreatedNotification as String,
        kAXMainWindowChangedNotification as String
    ]

    static let focusedWindowMovementNotificationNames = [
        kAXMovedNotification as String,
        kAXResizedNotification as String
    ]

    static let observedWindowNotificationNames = [
        kAXWindowMiniaturizedNotification as String,
        kAXWindowDeminiaturizedNotification as String,
        kAXTitleChangedNotification as String,
        kAXSelectedChildrenChangedNotification as String
    ]

    static func shouldUpdateFocusedWindowMovementObservation(for notificationName: String) -> Bool {
        notificationName == kAXFocusedWindowChangedNotification as String
            || notificationName == kAXMainWindowChangedNotification as String
    }

    static func shouldRefreshObservedWindowSet(for notificationName: String) -> Bool {
        notificationName == kAXFocusedWindowChangedNotification as String
            || notificationName == kAXMainWindowChangedNotification as String
            || notificationName == kAXWindowCreatedNotification as String
            || notificationName == kAXWindowMiniaturizedNotification as String
            || notificationName == kAXWindowDeminiaturizedNotification as String
            || notificationName == kAXSelectedChildrenChangedNotification as String
    }

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
                if ApplicationObserver.shouldUpdateFocusedWindowMovementObservation(for: notificationName) {
                    observer.updateFocusedWindowMovementObservation(for: app)
                }
                if ApplicationObserver.shouldRefreshObservedWindowSet(for: notificationName) {
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

        addNotifications(
            Self.appElementNotificationNames.filter { $0 != kAXFocusedWindowChangedNotification as String },
            to: appElement,
            observer: observer
        )

        focusedWindowObserver = observer
        observedFocusedWindowPid = app.processIdentifier
        observedAppElement = appElement
        updateFocusedWindowMovementObservation(for: app)
        updateWindowStateObservation(for: app)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func updateFocusedWindowMovementObservation(for app: NSRunningApplication) {
        guard let observer = focusedWindowObserver,
              app.processIdentifier == observedFocusedWindowPid else { return }

        if let window = observedFocusedWindow {
            removeNotifications(Self.focusedWindowMovementNotificationNames, from: window, observer: observer)
        }
        observedFocusedWindow = nil

        guard let window = focusedWindow(for: app) else { return }
        addNotifications(Self.focusedWindowMovementNotificationNames, to: window, observer: observer)
        observedFocusedWindow = window
    }

    private func updateWindowStateObservation(for app: NSRunningApplication) {
        guard let observer = focusedWindowObserver,
              app.processIdentifier == observedFocusedWindowPid else { return }

        for window in observedWindows {
            removeNotifications(Self.observedWindowNotificationNames, from: window, observer: observer)
        }
        observedWindows = windows(for: app)
        for window in observedWindows {
            addNotifications(Self.observedWindowNotificationNames, to: window, observer: observer)
        }
    }

    private func addNotifications(
        _ notificationNames: [String],
        to element: AXUIElement,
        observer: AXObserver
    ) {
        for notificationName in notificationNames {
            AXObserverAddNotification(
                observer,
                element,
                notificationName as CFString,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
    }

    private func removeNotifications(
        _ notificationNames: [String],
        from element: AXUIElement,
        observer: AXObserver
    ) {
        for notificationName in notificationNames {
            AXObserverRemoveNotification(observer, element, notificationName as CFString)
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
                removeNotifications(Self.appElementNotificationNames, from: appElement, observer: observer)
            }
            if let window = observedFocusedWindow {
                removeNotifications(Self.focusedWindowMovementNotificationNames, from: window, observer: observer)
            }
            for window in observedWindows {
                removeNotifications(Self.observedWindowNotificationNames, from: window, observer: observer)
            }
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
