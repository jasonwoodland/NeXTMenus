import XCTest
@testable import NeXTMenusKit

final class WindowSubmenuSynthesisTests: XCTestCase {
    func testOnlyWindowMenuUsesNonPressingWindowPresentation() {
        XCTAssertTrue(WindowSubmenuSynthesis.usesNonPressingWindowPresentation(menuTitle: "Window"))
        XCTAssertFalse(WindowSubmenuSynthesis.usesNonPressingWindowPresentation(menuTitle: "File"))
    }

    func testNonWindowMenuIsNotAugmented() {
        let existing = [makeMenuItem("Open")]
        let synthesized = [makeWindowItem("Info")]

        let result = WindowSubmenuSynthesis.augmentedItems(
            menuTitle: "File",
            existingItems: existing,
            synthesizedWindowItems: synthesized
        )

        XCTAssertEqual(result.map(\.title), ["Open"])
    }

    func testWindowMenuCanUseAXWindowsOnlyWhenNativeItemsAreEmpty() {
        let result = WindowSubmenuSynthesis.augmentedItems(
            menuTitle: "Window",
            existingItems: [],
            synthesizedWindowItems: [makeWindowItem("Info"), makeWindowItem("Logs")]
        )

        XCTAssertEqual(result.map(\.title), ["Info", "Logs"])
        XCTAssertTrue(result.allSatisfy { $0.actionKind == .raiseAXWindow })
    }

    func testWindowMenuPreservesExistingItemsAndAppendsMissingWindowsWithSeparator() {
        let existing = [makeMenuItem("Minimize"), makeMenuItem("Zoom")]
        let synthesized = [makeWindowItem("Info"), makeWindowItem("Logs")]

        let result = WindowSubmenuSynthesis.augmentedItems(
            menuTitle: "Window",
            existingItems: existing,
            synthesizedWindowItems: synthesized
        )

        XCTAssertEqual(result.map(\.title), ["Minimize", "Zoom", "", "Info", "Logs"])
        XCTAssertTrue(result[2].isSeparator)
        XCTAssertEqual(result[3].actionKind, .raiseAXWindow)
        XCTAssertEqual(result[4].actionKind, .raiseAXWindow)
    }

    func testWindowMenuDoesNotInsertDuplicateSeparator() {
        let existing = [makeMenuItem("Minimize"), makeSeparator()]

        let result = WindowSubmenuSynthesis.augmentedItems(
            menuTitle: "Window",
            existingItems: existing,
            synthesizedWindowItems: [makeWindowItem("Info")]
        )

        XCTAssertEqual(result.map(\.title), ["Minimize", "", "Info"])
        XCTAssertEqual(result.filter(\.isSeparator).count, 1)
    }

    func testWindowMenuAvoidsDuplicateTitlesAndIgnoresUntitledWindows() {
        let result = WindowSubmenuSynthesis.augmentedItems(
            menuTitle: "Window",
            existingItems: [makeMenuItem("Info")],
            synthesizedWindowItems: [
                makeWindowItem(""),
                makeWindowItem("Info"),
                makeWindowItem("Logs")
            ]
        )

        XCTAssertEqual(result.map(\.title), ["Info", "", "Logs"])
        XCTAssertEqual(result.last?.actionKind, .raiseAXWindow)
    }

    func testWindowMenuKeepsSynthesizedAXWindowOrder() {
        let result = WindowSubmenuSynthesis.augmentedItems(
            menuTitle: "Window",
            existingItems: [],
            synthesizedWindowItems: [
                makeWindowItem("Performance"),
                makeWindowItem("Scan"),
                makeWindowItem("Logs")
            ]
        )

        XCTAssertEqual(result.map(\.title), ["Performance", "Scan", "Logs"])
    }

    private func makeMenuItem(
        _ title: String,
        isSeparator: Bool = false,
        actionKind: MenuItemActionKind = .pressMenuItem
    ) -> MenuItem {
        MenuItem(
            title: title,
            isEnabled: !isSeparator,
            hasSubmenu: false,
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
            cmdModifiers: nil,
            actionKind: actionKind
        )
    }

    private func makeWindowItem(_ title: String) -> MenuItem {
        makeMenuItem(title, actionKind: .raiseAXWindow)
    }

    private func makeSeparator() -> MenuItem {
        makeMenuItem("", isSeparator: true)
    }
}
