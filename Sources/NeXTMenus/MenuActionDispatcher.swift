import ApplicationServices
import Cocoa
#if SWIFT_PACKAGE
import NeXTMenusKit
#endif

enum MenuActionDispatcher {
    static func axActionName(for actionKind: MenuItemActionKind) -> CFString {
        switch actionKind {
        case .pressMenuItem:
            return kAXPressAction as CFString
        case .raiseAXWindow:
            return kAXRaiseAction as CFString
        }
    }

    static func perform(
        actionKind: MenuItemActionKind,
        on element: AXUIElement,
        targetApp: NSRunningApplication?,
        delayAfterActivation: Bool = true
    ) {
        targetApp?.activate(options: [])
        if delayAfterActivation {
            usleep(50000)
        }
        AXUIElementPerformAction(element, axActionName(for: actionKind))
    }
}
