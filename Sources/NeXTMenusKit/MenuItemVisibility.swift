import Cocoa

public struct MenuModifierState: Equatable {
    public let hasOption: Bool
    public let hasShift: Bool
    public let hasControl: Bool

    public var showsAlternates: Bool {
        hasOption || hasShift || hasControl
    }

    public init(flags: NSEvent.ModifierFlags) {
        hasOption = flags.contains(.option)
        hasShift = flags.contains(.shift)
        hasControl = flags.contains(.control)
    }
}

public enum MenuItemVisibility {
    public static func visibleItems(from menuItems: [MenuItem],
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
                if matches(item.requiredModifiers, state: modifierState) {
                    filtered.append(item)
                }
                continue
            }

            // Hide the primary when its alternate (immediately after) is shown
            let alternateShown: Bool = {
                guard index + 1 < menuItems.count else { return false }
                let next = menuItems[index + 1]
                guard next.isAlternate, !next.isSeparator else { return false }
                return matches(next.requiredModifiers, state: modifierState)
            }()

            if !alternateShown {
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

    // True if the current modifier state satisfies an alternate item's
    // required modifier. nil/empty falls back to "any modifier shows it" so
    // older extracted items still work.
    private static func matches(_ required: NSEvent.ModifierFlags?,
                                state: MenuModifierState) -> Bool {
        guard let required = required, !required.isEmpty else {
            return state.showsAlternates
        }
        if required.contains(.option),  state.hasOption  { return true }
        if required.contains(.shift),   state.hasShift   { return true }
        if required.contains(.control), state.hasControl { return true }
        return false
    }
}
