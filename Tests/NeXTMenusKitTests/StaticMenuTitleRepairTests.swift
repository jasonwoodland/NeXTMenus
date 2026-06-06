import XCTest
@testable import NeXTMenusKit

final class StaticMenuTitleRepairTests: XCTestCase {
    func testRepairsBlankRuntimeTitleByIdentifier() {
        let runtime = [makeItem("", isSeparator: true, axIdentifier: "_NS:54")]
        let staticItems = [makeStaticItem(identifier: "_NS:54", title: "Info")]

        let repaired = StaticMenuTitleRepair.repairedItems(runtime, using: staticItems)

        XCTAssertEqual(repaired.map(\.title), ["Info"])
        XCTAssertFalse(repaired[0].isSeparator)
        XCTAssertEqual(repaired[0].axIdentifier, "_NS:54")
    }

    func testDoesNotOverwriteNonblankRuntimeTitle() {
        let runtime = [makeItem("Runtime Info", axIdentifier: "_NS:54")]
        let staticItems = [makeStaticItem(identifier: "_NS:54", title: "Static Info")]

        let repaired = StaticMenuTitleRepair.repairedItems(runtime, using: staticItems)

        XCTAssertEqual(repaired[0].title, "Runtime Info")
    }

    func testPreservesRuntimeOrderAndMetadata() {
        let runtime = [
            makeItem("First", isEnabled: false, axIdentifier: "first"),
            makeItem("", isEnabled: true, markChar: "✓", actionKind: .pressMenuItem, axIdentifier: "second"),
            makeItem("Third", actionKind: .raiseAXWindow, axIdentifier: "third")
        ]
        let staticItems = [makeStaticItem(identifier: "second", title: "Second")]

        let repaired = StaticMenuTitleRepair.repairedItems(runtime, using: staticItems)

        XCTAssertEqual(repaired.map(\.title), ["First", "Second", "Third"])
        XCTAssertFalse(repaired[0].isEnabled)
        XCTAssertEqual(repaired[1].markChar, "✓")
        XCTAssertEqual(repaired[1].actionKind, .pressMenuItem)
        XCTAssertEqual(repaired[2].actionKind, .raiseAXWindow)
        XCTAssertEqual(repaired.map(\.axIdentifier), ["first", "second", "third"])
    }

    func testNoOpsForMissingIdentifierMissingMatchAndAmbiguousMatch() {
        let runtime = [
            makeItem("", axIdentifier: nil),
            makeItem("", axIdentifier: "missing"),
            makeItem("", axIdentifier: "ambiguous")
        ]
        let staticItems = [
            makeStaticItem(identifier: "ambiguous", title: "One"),
            makeStaticItem(identifier: "ambiguous", title: "Two")
        ]

        let repaired = StaticMenuTitleRepair.repairedItems(runtime, using: staticItems)

        XCTAssertEqual(repaired.map(\.title), ["", "", ""])
        XCTAssertTrue(repaired.allSatisfy(\.isSeparator))
    }

    func testRepairsNestedSubmenuItems() {
        let child = makeItem("", axIdentifier: "child")
        let parent = makeItem(
            "Parent",
            hasSubmenu: true,
            submenuItems: [child],
            axIdentifier: "parent"
        )
        let staticItems = [
            makeStaticItem(
                identifier: "parent",
                title: "Static Parent",
                submenuItems: [makeStaticItem(identifier: "child", title: "Child")]
            )
        ]

        let repaired = StaticMenuTitleRepair.repairedItems([parent], using: staticItems)

        XCTAssertEqual(repaired[0].title, "Parent")
        XCTAssertEqual(repaired[0].submenuItems.map(\.title), ["Child"])
        XCTAssertFalse(repaired[0].submenuItems[0].isSeparator)
    }

    func testRepairedNativeWindowItemSuppressesDuplicateSynthesizedAXWindow() {
        let nativeRuntime = [makeItem("", actionKind: .pressMenuItem, axIdentifier: "_NS:54")]
        let staticItems = [makeStaticItem(identifier: "_NS:54", title: "Info")]
        let repairedNative = StaticMenuTitleRepair.repairedItems(nativeRuntime, using: staticItems)

        let result = WindowSubmenuSynthesis.augmentedItems(
            menuTitle: "Window",
            existingItems: repairedNative,
            synthesizedWindowItems: [makeItem("Info", actionKind: .raiseAXWindow)]
        )

        XCTAssertEqual(result.map(\.title), ["Info"])
        XCTAssertEqual(result[0].actionKind, .pressMenuItem)
        XCTAssertEqual(result[0].axIdentifier, "_NS:54")
    }

    private func makeStaticItem(
        identifier: String?,
        title: String,
        submenuItems: [StaticMenuItemMetadata] = []
    ) -> StaticMenuItemMetadata {
        StaticMenuItemMetadata(
            identifier: identifier,
            title: title,
            submenuItems: submenuItems
        )
    }

    private func makeItem(
        _ title: String,
        isEnabled: Bool = true,
        hasSubmenu: Bool = false,
        isSeparator: Bool? = nil,
        submenuItems: [MenuItem] = [],
        markChar: String? = nil,
        actionKind: MenuItemActionKind = .pressMenuItem,
        axIdentifier: String? = nil
    ) -> MenuItem {
        MenuItem(
            title: title,
            isEnabled: isEnabled,
            hasSubmenu: hasSubmenu,
            isSeparator: isSeparator ?? title.isEmpty,
            element: nil,
            submenuItems: submenuItems,
            keyEquivalent: nil,
            requiredModifiers: nil,
            isAlternate: false,
            alternateTitle: nil,
            cmdGlyph: nil,
            markChar: markChar,
            cmdChar: nil,
            cmdModifiers: nil,
            actionKind: actionKind,
            axIdentifier: axIdentifier
        )
    }
}
