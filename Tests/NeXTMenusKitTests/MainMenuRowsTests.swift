import Cocoa
import XCTest
@testable import NeXTMenusKit

final class MainMenuRowsTests: XCTestCase {
    func testInfoRowAlwaysExistsAndDefaultsSelectableWhenAppMenuIsNil() {
        let rows = MainMenuRows(
            appMenuItem: nil,
            visibleMenuItems: [],
            promotedAppMenuItems: [],
            trailingActions: []
        )

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.kind(at: 0), .appInfo)
        XCTAssertTrue(rows.isSelectable(row: 0))
        XCTAssertNil(rows.menuItem(at: 0))
    }

    func testDisabledAppMenuMakesInfoRowUnselectable() {
        let rows = MainMenuRows(
            appMenuItem: makeItem(title: "App", isEnabled: false),
            visibleMenuItems: [],
            promotedAppMenuItems: [],
            trailingActions: []
        )

        XCTAssertFalse(rows.isSelectable(row: 0))
        XCTAssertEqual(rows.menuItem(at: 0)?.title, "App")
    }

    func testVisiblePromotedAndTrailingRowsKeepExpectedOrdering() {
        let rows = MainMenuRows(
            appMenuItem: makeItem(title: "App"),
            visibleMenuItems: [makeItem(title: "File"), makeItem(title: "Edit")],
            promotedAppMenuItems: [makeItem(title: "Services")],
            trailingActions: [.hide, .quit]
        )

        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual((0..<rows.count).compactMap { rows.kind(at: $0) }, [
            .appInfo,
            .menuItem(index: 0),
            .menuItem(index: 1),
            .promotedAppMenuItem(index: 0),
            .trailingAction(.hide),
            .trailingAction(.quit)
        ])
        XCTAssertEqual((0..<rows.count).map { rows.menuItem(at: $0)?.title ?? "<action>" }, [
            "App", "File", "Edit", "Services", "<action>", "<action>"
        ])
    }

    func testSelectabilityMatchesCurrentMenuRules() {
        let rows = MainMenuRows(
            appMenuItem: makeItem(title: "App"),
            visibleMenuItems: [
                makeItem(title: "Enabled"),
                makeItem(title: "Disabled", isEnabled: false),
                makeSeparator()
            ],
            promotedAppMenuItems: [
                makeItem(title: "Services"),
                makeItem(title: "Disabled Service", isEnabled: false)
            ],
            trailingActions: [.hide]
        )

        XCTAssertEqual((0..<rows.count).map { rows.isSelectable(row: $0) }, [
            true,  // Info
            true,  // Enabled main item
            false, // Disabled main item
            false, // Separator main item
            true,  // Enabled promoted Services item
            false, // Disabled promoted item
            true   // Trailing action
        ])
    }

    func testTrailingActionsFromConfigurationPreserveOrderingAndFinderLogOut() {
        XCTAssertEqual(
            MainMenuRows.trailingActions(showHide: false, showQuit: false, isFinderTarget: false),
            []
        )
        XCTAssertEqual(
            MainMenuRows.trailingActions(showHide: true, showQuit: false, isFinderTarget: false),
            [.hide]
        )
        XCTAssertEqual(
            MainMenuRows.trailingActions(showHide: false, showQuit: true, isFinderTarget: false),
            [.quit]
        )
        XCTAssertEqual(
            MainMenuRows.trailingActions(showHide: true, showQuit: true, isFinderTarget: false),
            [.hide, .quit]
        )
        XCTAssertEqual(
            MainMenuRows.trailingActions(showHide: true, showQuit: true, isFinderTarget: true),
            [.hide, .logOut]
        )
    }

    func testControllerFacingVisibilityConfigurationPreservesSeparators() {
        let visibleMenuItems = MenuItemVisibility.visibleItems(
            from: [
                makeItem(title: "File"),
                makeSeparator(),
                makeItem(title: "Edit")
            ],
            modifierState: MenuModifierState(flags: []),
            trimSeparators: false
        )
        let rows = MainMenuRows(
            appMenuItem: makeItem(title: "App"),
            visibleMenuItems: visibleMenuItems,
            promotedAppMenuItems: [],
            trailingActions: []
        )

        XCTAssertEqual((0..<rows.count).compactMap { rows.kind(at: $0) }, [
            .appInfo,
            .menuItem(index: 0),
            .menuItem(index: 1),
            .menuItem(index: 2)
        ])
        XCTAssertEqual((0..<rows.count).map { rows.menuItem(at: $0)?.title ?? "<nil>" }, [
            "App", "File", "", "Edit"
        ])
        XCTAssertFalse(rows.isSelectable(row: 2))
    }

    func testPromotedServicesProjectionMatchesCurrentPredicate() {
        let projected = MainMenuRows.promotedServicesItems(
            from: [
                makeSeparator(),
                makeItem(title: "About"),
                makeItem(title: "Services"),
                makeItem(title: "Services", isSeparator: true),
                makeItem(title: "Other Services")
            ],
            showServices: true
        )

        XCTAssertEqual(projected.map(\.title), ["Services"])
        XCTAssertTrue(MainMenuRows.promotedServicesItems(from: projected, showServices: false).isEmpty)
    }

    func testOutOfRangeRowsReturnNilAndAreNotSelectable() {
        let rows = MainMenuRows(
            appMenuItem: nil,
            visibleMenuItems: [makeItem(title: "File")],
            promotedAppMenuItems: [],
            trailingActions: []
        )

        XCTAssertNil(rows.kind(at: -1))
        XCTAssertNil(rows.kind(at: 2))
        XCTAssertNil(rows.menuItem(at: -1))
        XCTAssertNil(rows.menuItem(at: 2))
        XCTAssertNil(rows.trailingAction(at: -1))
        XCTAssertNil(rows.trailingAction(at: 2))
        XCTAssertFalse(rows.isSelectable(row: -1))
        XCTAssertFalse(rows.isSelectable(row: 2))
    }

    private func makeItem(
        title: String,
        isEnabled: Bool = true,
        hasSubmenu: Bool = false,
        isSeparator: Bool = false
    ) -> MenuItem {
        MenuItem(
            title: title,
            isEnabled: isEnabled,
            hasSubmenu: hasSubmenu,
            isSeparator: isSeparator,
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

    private func makeSeparator() -> MenuItem {
        makeItem(title: "", isEnabled: false, isSeparator: true)
    }
}
