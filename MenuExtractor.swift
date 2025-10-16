import Cocoa
import ApplicationServices

struct MenuItem {
    let title: String
    let isEnabled: Bool
    let hasSubmenu: Bool
    let element: AXUIElement?
    let submenuItems: [MenuItem]
}

class MenuExtractor {
    static func extractMenuItems(from app: NSRunningApplication) -> (appMenuItem: MenuItem?, menuItems: [MenuItem]) {
        var items: [MenuItem] = []
        var appMenuItem: MenuItem?

        // Get the accessibility element for the application
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Get the menu bar
        var menuBarValue: AnyObject?
        let menuBarResult = AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarValue)

        guard menuBarResult == .success,
              let menuBar = menuBarValue else {
            return (nil, items)
        }

        // Get the children of the menu bar (menu bar items)
        var childrenValue: AnyObject?
        let childrenResult = AXUIElementCopyAttributeValue(menuBar as! AXUIElement, kAXChildrenAttribute as CFString, &childrenValue)

        guard childrenResult == .success,
              let children = childrenValue as? [AXUIElement] else {
            return (nil, items)
        }

        let appName = app.localizedName ?? ""

        // Extract each menu bar item (without extracting submenus)
        for (index, child) in children.enumerated() {
            if let menuItem = extractMenuItem(from: child, extractSubmenu: false) {
                // First item (index 0) is usually the Apple menu - skip it
                // Second item (index 1) is usually the app name menu - save as appMenuItem
                if index == 0 {
                    continue // Skip Apple menu
                } else if index == 1 && (menuItem.title == appName || menuItem.title.isEmpty) {
                    appMenuItem = menuItem // Save app menu
                } else {
                    items.append(menuItem)
                }
            }
        }

        return (appMenuItem, items)
    }

    private static func extractMenuItem(from element: AXUIElement, extractSubmenu: Bool = false) -> MenuItem? {
        // Get the title
        var titleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
        let title = titleValue as? String ?? ""

        // Skip empty titles (usually the app icon menu)
        if title.isEmpty {
            return nil
        }

        // Get enabled state
        var enabledValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabledValue)
        let isEnabled = (enabledValue as? Bool) ?? true

        // For now, we'll extract submenus on-demand, not during initialization
        return MenuItem(title: title, isEnabled: isEnabled, hasSubmenu: true, element: element, submenuItems: [])
    }

    // Extract submenu items on-demand from a menu bar item
    static func extractSubmenuItemsOnDemand(from element: AXUIElement) -> [MenuItem] {
        // First, try to get children without pressing (may not work for all apps)
        var childrenValue: AnyObject?
        var result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)

        // If no children found, we need to press the item to populate them
        var didPress = false
        if result != .success || (childrenValue as? [AXUIElement])?.isEmpty ?? true {
            // Press the menu item to populate its children
            AXUIElementPerformAction(element, kAXPressAction as CFString)
            didPress = true

            // Minimal delay to allow menu to populate
            usleep(50000) // 50ms

            // Try to get children again
            result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
        }

        // If we pressed, cancel immediately to minimize visual disruption
        if didPress {
            AXUIElementPerformAction(element, kAXCancelAction as CFString)
        }

        guard result == .success,
              let children = childrenValue as? [AXUIElement],
              !children.isEmpty else {
            return []
        }

        return extractSubmenuItems(from: children)
    }

    static func extractSubmenuItems(from children: [AXUIElement]) -> [MenuItem] {
        var items: [MenuItem] = []

        for child in children {
            // Get the role to identify the element type
            var roleValue: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue)
            let role = roleValue as? String ?? ""

            // If this is an AXMenu, we need to get its children (the actual menu items)
            if role == kAXMenuRole as String {
                var menuChildrenValue: AnyObject?
                AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &menuChildrenValue)
                if let menuChildren = menuChildrenValue as? [AXUIElement] {
                    // Recursively extract items from the menu
                    items.append(contentsOf: extractSubmenuItems(from: menuChildren))
                }
                continue
            }

            // Only process menu items
            guard role == kAXMenuItemRole as String else {
                continue
            }

            // Get the title
            var titleValue: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleValue)
            let title = titleValue as? String ?? ""

            // Get enabled state
            var enabledValue: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXEnabledAttribute as CFString, &enabledValue)
            let isEnabled = (enabledValue as? Bool) ?? true

            // Check for submenu
            var childrenValue: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &childrenValue)
            let hasSubmenu = (childrenValue as? [AXUIElement])?.isEmpty == false

            items.append(MenuItem(title: title, isEnabled: isEnabled, hasSubmenu: hasSubmenu, element: child, submenuItems: []))
        }

        return items
    }
}
