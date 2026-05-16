import Cocoa
import ApplicationServices

struct MenuItem {
    let title: String
    let isEnabled: Bool
    let hasSubmenu: Bool
    let isSeparator: Bool
    let element: AXUIElement?
    var submenuItems: [MenuItem]

    // Modifier key support
    let keyEquivalent: String? // Keyboard shortcut (e.g., "⌘S")
    let requiredModifiers: NSEvent.ModifierFlags? // Modifiers required for this item to be visible
    let isAlternate: Bool // Whether this is an alternate menu item (shown only with modifiers)
    let alternateTitle: String? // Title to show when modifiers are held (e.g., "Save As..." becomes "Save...")

    // AXMenuItem attributes
    let cmdGlyph: Int? // kAXMenuItemCmdGlyph - special-key glyph code for the shortcut
    let markChar: String? // kAXMenuItemMarkChar - mark character (e.g. "✓" for checked items)
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
        return MenuItem(
            title: title,
            isEnabled: isEnabled,
            hasSubmenu: true,
            isSeparator: false,
            element: element,
            submenuItems: [],
            keyEquivalent: nil,
            requiredModifiers: nil,
            isAlternate: false,
            alternateTitle: nil,
            cmdGlyph: nil,
            markChar: nil
        )
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

    // Extract the full menu tree for an application, including every submenu.
    // This presses every submenu in the target app, so it is slow and visually
    // disruptive - run it off the main thread, up front.
    static func extractFullMenu(from app: NSRunningApplication) -> (appMenuItem: MenuItem?, menuItems: [MenuItem]) {
        var (appMenuItem, menuItems) = extractMenuItems(from: app)

        for index in menuItems.indices {
            if let element = menuItems[index].element {
                menuItems[index].submenuItems = extractSubmenuTree(from: element)
            }
        }
        if let appElement = appMenuItem?.element {
            appMenuItem?.submenuItems = extractSubmenuTree(from: appElement)
        }
        return (appMenuItem, menuItems)
    }

    // Recursively extract the entire submenu tree beneath a menu element,
    // populating each item's `submenuItems`.
    static func extractSubmenuTree(from element: AXUIElement, depth: Int = 0) -> [MenuItem] {
        guard depth < 12 else { return [] }

        var items = extractSubmenuItemsOnDemand(from: element)
        for index in items.indices {
            let item = items[index]
            guard item.hasSubmenu, let childElement = item.element else { continue }
            items[index].submenuItems = extractSubmenuTree(from: childElement, depth: depth + 1)
        }
        return items
    }

    // Returns a menu item's submenu items, preferring the pre-extracted cache
    // and falling back to on-demand extraction if the cache is empty.
    static func submenuItems(for menuItem: MenuItem) -> [MenuItem] {
        if !menuItem.submenuItems.isEmpty {
            return menuItem.submenuItems
        }
        guard let element = menuItem.element else { return [] }
        return extractSubmenuItemsOnDemand(from: element)
    }

    static func extractSubmenuItems(from children: [AXUIElement]) -> [MenuItem] {
        var allItems: [MenuItem] = []

        // First pass: extract all items
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
                    allItems.append(contentsOf: extractSubmenuItems(from: menuChildren))
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

            // Check if this is a separator (empty title or contains only dashes/spaces)
            let isSeparator = title.isEmpty || title.trimmingCharacters(in: .whitespaces).allSatisfy { $0 == "-" }

            // Get enabled state
            var enabledValue: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXEnabledAttribute as CFString, &enabledValue)
            let isEnabled = (enabledValue as? Bool) ?? true

            // Check for submenu
            var childrenValue: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &childrenValue)
            let hasSubmenu = (childrenValue as? [AXUIElement])?.isEmpty == false

            // Extract keyboard shortcut, modifier, and glyph info
            var keyEquivalentValue: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXMenuItemCmdCharAttribute as CFString, &keyEquivalentValue)
            let keyChar = keyEquivalentValue as? String

            var modifiersValue: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXMenuItemCmdModifiersAttribute as CFString, &modifiersValue)
            let modifiers = modifiersValue as? Int

            // kAXMenuItemCmdGlyph - used when the shortcut key is a special key
            // (arrows, return, etc.) rather than a printable character
            var glyphValue: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXMenuItemCmdGlyphAttribute as CFString, &glyphValue)
            let cmdGlyph = (glyphValue as? Int).flatMap { $0 == 0 ? nil : $0 }

            // kAXMenuItemMarkChar - mark character (e.g. "✓" for checked items)
            var markValue: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXMenuItemMarkCharAttribute as CFString, &markValue)
            let markChar = (markValue as? String).flatMap { str -> String? in
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }

            // Resolve the shortcut key. A printable character is used as-is;
            // a control/whitespace character (return, tab, delete, …) is not
            // renderable, so fall back to the glyph or a control-key symbol.
            var shortcutKey: String? = nil
            if let keyChar = keyChar, let scalar = keyChar.unicodeScalars.first {
                if let fnSymbol = functionKeySymbol(scalar) {
                    // Arrows / F-keys arrive as private-use characters that
                    // render as a missing glyph - map them to key symbols.
                    shortcutKey = fnSymbol
                } else if CharacterSet.controlCharacters.contains(scalar)
                    || CharacterSet.whitespacesAndNewlines.contains(scalar) {
                    shortcutKey = cmdGlyph.flatMap { glyphSymbol(for: $0) }
                        ?? controlCharSymbol(scalar)
                } else {
                    shortcutKey = keyChar.uppercased()
                }
            } else if let cmdGlyph = cmdGlyph {
                shortcutKey = glyphSymbol(for: cmdGlyph)
            }

            // Build the key equivalent string. The cmd-modifiers mask uses
            // Carbon semantics: Command is implied unless the "no command" bit
            // (8) is set; bits 1/2/4 add Shift/Option/Control.
            var keyEquivalent: String? = nil
            if let shortcutKey = shortcutKey {
                let mods = modifiers ?? 0
                var keyString = ""
                if mods & 4 != 0 { keyString += "⌃" } // Control
                if mods & 2 != 0 { keyString += "⌥" } // Option
                if mods & 1 != 0 { keyString += "⇧" } // Shift
                if mods & 8 == 0 { keyString += "⌘" } // Command (implied unless suppressed)
                keyString += shortcutKey
                keyEquivalent = keyString
            }

            allItems.append(MenuItem(
                title: title,
                isEnabled: isEnabled,
                hasSubmenu: hasSubmenu,
                isSeparator: isSeparator,
                element: child,
                submenuItems: [],
                keyEquivalent: keyEquivalent,
                requiredModifiers: nil,
                isAlternate: false,
                alternateTitle: nil,
                cmdGlyph: cmdGlyph,
                markChar: markChar
            ))
        }

        // Second pass: identify alternates
        // Look for consecutive items that appear to be alternates of each other
        for i in 0..<allItems.count {
            guard i + 1 < allItems.count else { continue }

            let item1 = allItems[i]
            let item2 = allItems[i + 1]

            // Skip if either is a separator
            if item1.isSeparator || item2.isSeparator { continue }

            // Skip if they have different enabled states or submenu status
            if item1.isEnabled != item2.isEnabled || item1.hasSubmenu != item2.hasSubmenu { continue }

            let title1 = item1.title.lowercased()
            let title2 = item2.title.lowercased()

            // Check if they're alternates based on common patterns
            let areAlternates = checkIfAlternates(title1: title1, title2: title2)

            if areAlternates {
                // Mark the appropriate one as alternate
                // Usually the longer/more specific one is the alternate
                if title2.contains("all") || title2.contains("alternative") ||
                   title2.count > title1.count {
                    // Second item is the alternate (shown with modifiers)
                    allItems[i + 1] = MenuItem(
                        title: item2.title,
                        isEnabled: item2.isEnabled,
                        hasSubmenu: item2.hasSubmenu,
                        isSeparator: item2.isSeparator,
                        element: item2.element,
                        submenuItems: item2.submenuItems,
                        keyEquivalent: item2.keyEquivalent,
                        requiredModifiers: .option,
                        isAlternate: true,
                        alternateTitle: nil,
                        cmdGlyph: item2.cmdGlyph,
                        markChar: item2.markChar
                    )
                } else if title1.contains("all") || title1.contains("alternative") {
                    // First item is the alternate
                    allItems[i] = MenuItem(
                        title: item1.title,
                        isEnabled: item1.isEnabled,
                        hasSubmenu: item1.hasSubmenu,
                        isSeparator: item1.isSeparator,
                        element: item1.element,
                        submenuItems: item1.submenuItems,
                        keyEquivalent: item1.keyEquivalent,
                        requiredModifiers: .option,
                        isAlternate: true,
                        alternateTitle: nil,
                        cmdGlyph: item1.cmdGlyph,
                        markChar: item1.markChar
                    )
                }
            }
        }

        return allItems
    }

    // Maps a kAXMenuItemCmdGlyph code (Carbon Menus.h glyph constants) to a
    // display symbol, for shortcuts that use a special key instead of a char.
    private static func glyphSymbol(for glyph: Int) -> String? {
        switch glyph {
        case 0x02, 0x03: return "⇥"  // tab right / tab left
        case 0x04:       return "⌅"  // enter
        case 0x09:       return "␣"  // space
        case 0x0A:       return "⌦"  // delete right (forward delete)
        case 0x0B, 0x0D: return "↩"  // return / non-marking return
        case 0x17:       return "⌫"  // delete left (backspace)
        case 0x1B:       return "⎋"  // escape
        case 0x1C:       return "⌧"  // clear
        case 0x18, 0x64: return "◀"  // left arrow
        case 0x1A, 0x65: return "▶"  // right arrow
        case 0x19, 0x68: return "▲"  // up arrow
        case 0x10, 0x6A: return "▼"  // down arrow
        case 0x62:       return "⇞"  // page up
        case 0x6B:       return "⇟"  // page down
        case 0x66:       return "↖"  // home
        case 0x69:       return "↘"  // end
        case 0x8C:       return "⏏"  // eject
        case 0x6F...0x7D: return "F\(glyph - 0x6F + 1)"  // F1...F15
        default:         return nil
        }
    }

    // Maps a function-key private-use character (NSUpArrowFunctionKey etc.)
    // to a renderable key symbol. These would otherwise show as a missing
    // glyph in the shortcut text.
    private static func functionKeySymbol(_ scalar: Unicode.Scalar) -> String? {
        switch scalar.value {
        case 0xF700: return "▲"   // up arrow
        case 0xF701: return "▼"   // down arrow
        case 0xF702: return "◀"   // left arrow
        case 0xF703: return "▶"   // right arrow
        case 0xF728: return "⌦"   // forward delete
        case 0xF729: return "↖"   // home
        case 0xF72B: return "↘"   // end
        case 0xF72C: return "⇞"   // page up
        case 0xF72D: return "⇟"   // page down
        case 0xF704...0xF726: return "F\(scalar.value - 0xF704 + 1)"  // F1–F35
        default:    return nil
        }
    }

    // Maps a control/whitespace shortcut character to its key symbol, for the
    // cases where macOS reports the character instead of a glyph code.
    private static func controlCharSymbol(_ scalar: Unicode.Scalar) -> String? {
        switch scalar.value {
        case 0x0D, 0x03, 0x0A: return "↩"  // return / enter / newline
        case 0x09:             return "⇥"  // tab
        case 0x08, 0x7F:       return "⌫"  // backspace / delete
        case 0x1B:             return "⎋"  // escape
        case 0x20:             return "␣"  // space
        default:               return nil
        }
    }

    // Helper function to check if two titles are alternates
    private static func checkIfAlternates(title1: String, title2: String) -> Bool {
        // Common alternate patterns

        // Pattern 1: One contains "all" (e.g., "Close" vs "Close All")
        if (title1.contains("all") && !title2.contains("all")) ||
           (title2.contains("all") && !title1.contains("all")) {
            // Check if they share a common base
            let base1 = title1.replacingOccurrences(of: " all", with: "").replacingOccurrences(of: "all ", with: "")
            let base2 = title2.replacingOccurrences(of: " all", with: "").replacingOccurrences(of: "all ", with: "")
            if base1 == base2 || title1.contains(base2) || title2.contains(base1) {
                return true
            }
        }

        // Pattern 2: One is a substring of the other (e.g., "Quit" vs "Quit and Keep Windows")
        if title1.contains(title2) || title2.contains(title1) {
            return true
        }

        // Pattern 3: They differ only by ellipsis
        if title1.replacingOccurrences(of: "...", with: "") == title2.replacingOccurrences(of: "...", with: "") ||
           title1.replacingOccurrences(of: "…", with: "") == title2.replacingOccurrences(of: "…", with: "") {
            return true
        }

        // Pattern 4: Show/Hide alternates
        if (title1.contains("show") && title2.contains("hide")) ||
           (title1.contains("hide") && title2.contains("show")) {
            let base1 = title1.replacingOccurrences(of: "show", with: "").replacingOccurrences(of: "hide", with: "")
            let base2 = title2.replacingOccurrences(of: "show", with: "").replacingOccurrences(of: "hide", with: "")
            if base1 == base2 {
                return true
            }
        }

        return false
    }
}
