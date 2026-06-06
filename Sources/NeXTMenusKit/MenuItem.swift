import ApplicationServices
import Cocoa

public enum MenuItemActionKind: Equatable {
    case pressMenuItem
    case raiseAXWindow
}

public struct MenuItem {
    public let title: String
    public let isEnabled: Bool
    public let hasSubmenu: Bool
    public let isSeparator: Bool
    public let element: AXUIElement?
    public var submenuItems: [MenuItem]

    // Modifier key support
    public let keyEquivalent: String? // Keyboard shortcut (e.g., "⌘S")
    public let requiredModifiers: NSEvent.ModifierFlags? // Modifiers required for this item to be visible
    public let isAlternate: Bool // Whether this is an alternate menu item (shown only with modifiers)
    public let alternateTitle: String? // Title to show when modifiers are held (e.g., "Save As..." becomes "Save...")

    // AXMenuItem attributes
    public let cmdGlyph: Int? // kAXMenuItemCmdGlyph - special-key glyph code for the shortcut
    public var markChar: String? // kAXMenuItemMarkChar - mark character (e.g. "✓" for checked items)
    public let cmdChar: String? // kAXMenuItemCmdChar - raw shortcut character (used to detect alternates)
    public let cmdModifiers: Int? // kAXMenuItemCmdModifiers - raw modifier mask (used to detect alternates)
    public let actionKind: MenuItemActionKind
    public let axIdentifier: String?

    public init(
        title: String,
        isEnabled: Bool,
        hasSubmenu: Bool,
        isSeparator: Bool,
        element: AXUIElement?,
        submenuItems: [MenuItem],
        keyEquivalent: String?,
        requiredModifiers: NSEvent.ModifierFlags?,
        isAlternate: Bool,
        alternateTitle: String?,
        cmdGlyph: Int?,
        markChar: String?,
        cmdChar: String?,
        cmdModifiers: Int?,
        actionKind: MenuItemActionKind = .pressMenuItem,
        axIdentifier: String? = nil
    ) {
        self.title = title
        self.isEnabled = isEnabled
        self.hasSubmenu = hasSubmenu
        self.isSeparator = isSeparator
        self.element = element
        self.submenuItems = submenuItems
        self.keyEquivalent = keyEquivalent
        self.requiredModifiers = requiredModifiers
        self.isAlternate = isAlternate
        self.alternateTitle = alternateTitle
        self.cmdGlyph = cmdGlyph
        self.markChar = markChar
        self.cmdChar = cmdChar
        self.cmdModifiers = cmdModifiers
        self.actionKind = actionKind
        self.axIdentifier = axIdentifier
    }
}
