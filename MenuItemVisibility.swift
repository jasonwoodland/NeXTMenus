import Cocoa

struct MenuModifierState: Equatable {
    let hasOption: Bool
    let hasShift: Bool
    let hasControl: Bool

    var showsAlternates: Bool {
        hasOption || hasShift || hasControl
    }

    init(flags: NSEvent.ModifierFlags) {
        hasOption = flags.contains(.option)
        hasShift = flags.contains(.shift)
        hasControl = flags.contains(.control)
    }
}

enum NextMenusRendering {
    // Default to the original glass rendering. Set NEXTMENUS_LOW_POWER=1 to
    // use simple opaque drawing while profiling WindowServer CPU.
    static let useGlassEffects = ProcessInfo.processInfo.environment["NEXTMENUS_LOW_POWER"] != "1"

    static var windowBackgroundColor: NSColor {
        NSColor.windowBackgroundColor
    }

    static var selectionBackgroundColor: NSColor {
        NSColor.selectedContentBackgroundColor
    }

    static func makeSelectionBackground(frame: NSRect) -> NSView {
        if useGlassEffects {
            let backgroundView = NSVisualEffectView(frame: frame)
            backgroundView.material = .selection
            backgroundView.blendingMode = .withinWindow
            backgroundView.state = .active
            backgroundView.isEmphasized = true
            backgroundView.wantsLayer = true
            backgroundView.layer?.cornerRadius = 8
            backgroundView.layer?.cornerCurve = .continuous
            backgroundView.layer?.masksToBounds = true
            return backgroundView
        }

        let backgroundView = NSView(frame: frame)
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = selectionBackgroundColor.cgColor
        backgroundView.layer?.cornerRadius = 8
        backgroundView.layer?.cornerCurve = .continuous
        backgroundView.layer?.masksToBounds = true
        return backgroundView
    }
}

enum MenuItemVisibility {
    static func visibleItems(from menuItems: [MenuItem],
                             modifierState: MenuModifierState,
                             trimSeparators: Bool) -> [MenuItem] {
        var filtered: [MenuItem] = []
        filtered.reserveCapacity(menuItems.count)

        for (index, item) in menuItems.enumerated() {
            if item.isSeparator {
                filtered.append(item)
                continue
            }

            if item.isAlternate {
                if modifierState.showsAlternates {
                    filtered.append(item)
                }
                continue
            }

            let hasAlternateImmediatelyAfter: Bool
            if index + 1 < menuItems.count {
                let nextItem = menuItems[index + 1]
                hasAlternateImmediatelyAfter = nextItem.isAlternate && !nextItem.isSeparator
            } else {
                hasAlternateImmediatelyAfter = false
            }

            if !hasAlternateImmediatelyAfter || !modifierState.showsAlternates {
                filtered.append(item)
            }
        }

        guard trimSeparators else { return filtered }

        var result: [MenuItem] = []
        result.reserveCapacity(filtered.count)
        for item in filtered {
            if item.isSeparator && (result.last?.isSeparator ?? true) {
                continue
            }
            result.append(item)
        }
        if result.last?.isSeparator == true {
            result.removeLast()
        }
        return result
    }
}
