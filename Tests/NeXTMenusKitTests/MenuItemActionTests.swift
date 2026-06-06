import XCTest
@testable import NeXTMenusKit

final class MenuItemActionTests: XCTestCase {
    func testMenuItemsDefaultToPressMenuItemAction() {
        let item = makeItem(title: "Open")

        XCTAssertEqual(item.actionKind, .pressMenuItem)
    }

    func testMenuItemsCanRepresentRaiseAXWindowAction() {
        let item = makeItem(title: "Info", actionKind: .raiseAXWindow)

        XCTAssertEqual(item.actionKind, .raiseAXWindow)
    }

    private func makeItem(
        title: String,
        actionKind: MenuItemActionKind = .pressMenuItem
    ) -> MenuItem {
        MenuItem(
            title: title,
            isEnabled: true,
            hasSubmenu: false,
            isSeparator: false,
            element: nil,
            submenuItems: [],
            keyEquivalent: nil,
            requiredModifiers: nil,
            isAlternate: false,
            alternateTitle: nil,
            cmdGlyph: nil,
            markChar: nil,
            cmdChar: nil,
            cmdModifiers: nil,
            actionKind: actionKind
        )
    }
}
