import Cocoa
import XCTest
@testable import NeXTMenusKit

final class MenuItemVisibilityTests: XCTestCase {
    func testOptionAlternateReplacesImmediatelyPrecedingPrimary() {
        let primary = makeItem(title: "Save As…")
        let alternate = makeItem(
            title: "Duplicate",
            requiredModifiers: .option,
            isAlternate: true,
            alternateTitle: "Save As…"
        )

        let defaultItems = MenuItemVisibility.visibleItems(
            from: [primary, alternate],
            modifierState: MenuModifierState(flags: []),
            trimSeparators: true
        )
        XCTAssertEqual(defaultItems.map(\.title), ["Save As…"])

        let optionItems = MenuItemVisibility.visibleItems(
            from: [primary, alternate],
            modifierState: MenuModifierState(flags: [.option]),
            trimSeparators: true
        )
        XCTAssertEqual(optionItems.map(\.title), ["Duplicate"])
    }

    func testAlternatesWithoutSpecificModifierShowForAnyModifier() {
        let primary = makeItem(title: "Close")
        let alternate = makeItem(
            title: "Close All",
            isAlternate: true,
            alternateTitle: "Close"
        )

        let defaultItems = MenuItemVisibility.visibleItems(
            from: [primary, alternate],
            modifierState: MenuModifierState(flags: []),
            trimSeparators: true
        )
        XCTAssertEqual(defaultItems.map(\.title), ["Close"])

        let shiftItems = MenuItemVisibility.visibleItems(
            from: [primary, alternate],
            modifierState: MenuModifierState(flags: [.shift]),
            trimSeparators: true
        )
        XCTAssertEqual(shiftItems.map(\.title), ["Close All"])
    }

    func testSpecificAlternateModifierMustMatch() {
        let primary = makeItem(title: "Minimize")
        let alternate = makeItem(
            title: "Minimize All",
            requiredModifiers: .option,
            isAlternate: true,
            alternateTitle: "Minimize"
        )

        let shiftItems = MenuItemVisibility.visibleItems(
            from: [primary, alternate],
            modifierState: MenuModifierState(flags: [.shift]),
            trimSeparators: true
        )
        XCTAssertEqual(shiftItems.map(\.title), ["Minimize"])

        let optionItems = MenuItemVisibility.visibleItems(
            from: [primary, alternate],
            modifierState: MenuModifierState(flags: [.option]),
            trimSeparators: true
        )
        XCTAssertEqual(optionItems.map(\.title), ["Minimize All"])
    }

    func testSeparatorTrimmingRemovesLeadingTrailingAndDuplicateSeparators() {
        let visibleItems = MenuItemVisibility.visibleItems(
            from: [
                makeSeparator(),
                makeItem(title: "Open"),
                makeSeparator(),
                makeSeparator(),
                makeItem(title: "Close"),
                makeSeparator()
            ],
            modifierState: MenuModifierState(flags: []),
            trimSeparators: true
        )

        XCTAssertEqual(visibleItems.map(\.title), ["Open", "", "Close"])
        XCTAssertEqual(visibleItems.map(\.isSeparator), [false, true, false])
    }

    private func makeItem(
        title: String,
        isEnabled: Bool = true,
        hasSubmenu: Bool = false,
        requiredModifiers: NSEvent.ModifierFlags? = nil,
        isAlternate: Bool = false,
        alternateTitle: String? = nil,
        keyEquivalent: String? = nil,
        cmdChar: String? = nil,
        cmdModifiers: Int? = nil,
        markChar: String? = nil
    ) -> MenuItem {
        MenuItem(
            title: title,
            isEnabled: isEnabled,
            hasSubmenu: hasSubmenu,
            isSeparator: false,
            element: nil,
            submenuItems: [],
            keyEquivalent: keyEquivalent,
            requiredModifiers: requiredModifiers,
            isAlternate: isAlternate,
            alternateTitle: alternateTitle,
            cmdGlyph: nil,
            markChar: markChar,
            cmdChar: cmdChar,
            cmdModifiers: cmdModifiers
        )
    }

    private func makeSeparator() -> MenuItem {
        MenuItem(
            title: "",
            isEnabled: false,
            hasSubmenu: false,
            isSeparator: true,
            element: nil,
            submenuItems: [],
            keyEquivalent: nil,
            requiredModifiers: nil,
            isAlternate: false,
            alternateTitle: nil,
            cmdGlyph: nil,
            markChar: nil,
            cmdChar: nil,
            cmdModifiers: nil
        )
    }
}
