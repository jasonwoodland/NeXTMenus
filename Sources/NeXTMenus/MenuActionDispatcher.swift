import ApplicationServices
import Cocoa
#if SWIFT_PACKAGE
import NeXTMenusKit
#endif

enum MenuActionOperation: Equatable {
    case setMinimized(Bool)
    case performAction(String)
}

enum MenuActionDispatcher {
    static func axActionName(for actionKind: MenuItemActionKind) -> CFString {
        switch actionKind {
        case .pressMenuItem:
            return kAXPressAction as CFString
        case .raiseAXWindow:
            return kAXRaiseAction as CFString
        }
    }

    static func actionPlan(
        for actionKind: MenuItemActionKind,
        isMinimized: Bool
    ) -> [MenuActionOperation] {
        switch actionKind {
        case .pressMenuItem:
            return [.performAction(kAXPressAction as String)]
        case .raiseAXWindow:
            var operations = [MenuActionOperation]()
            if isMinimized {
                operations.append(.setMinimized(false))
            }
            operations.append(.performAction(kAXRaiseAction as String))
            return operations
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

        let isMinimized = actionKind == .raiseAXWindow && isMinimized(element)
        for operation in actionPlan(for: actionKind, isMinimized: isMinimized) {
            perform(operation, on: element)
        }
    }

    private static func perform(_ operation: MenuActionOperation, on element: AXUIElement) {
        switch operation {
        case .setMinimized(let minimized):
            let value = (minimized ? kCFBooleanTrue : kCFBooleanFalse)!
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, value)
        case .performAction(let actionName):
            AXUIElementPerformAction(element, actionName as CFString)
        }
    }

    private static func isMinimized(_ element: AXUIElement) -> Bool {
        var minimizedValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXMinimizedAttribute as CFString,
            &minimizedValue
        )
        guard result == .success else { return false }
        return (minimizedValue as? Bool) ?? false
    }
}
