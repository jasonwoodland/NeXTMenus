import ApplicationServices
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

    func testWindowMarkUsesDiamondForMinimizedWindows() {
        XCTAssertEqual(WindowSubmenuSynthesis.windowMarkChar(isFocused: false, isMinimized: true), "◆")
        XCTAssertEqual(WindowSubmenuSynthesis.windowMarkChar(isFocused: true, isMinimized: true), "◆")
        XCTAssertEqual(WindowSubmenuSynthesis.windowMarkChar(isFocused: true, isMinimized: false), "✓")
        XCTAssertNil(WindowSubmenuSynthesis.windowMarkChar(isFocused: false, isMinimized: false))
    }

    func testMinimizedSynthesizedWindowKeepsDiamondAndRaiseAction() {
        let result = WindowSubmenuSynthesis.augmentedItems(
            menuTitle: "Window",
            existingItems: [],
            synthesizedWindowItems: [makeWindowItem("Scan", markChar: "◆")]
        )

        XCTAssertEqual(result.map(\.title), ["Scan"])
        XCTAssertEqual(result.first?.markChar, "◆")
        XCTAssertEqual(result.first?.actionKind, .raiseAXWindow)
    }

    func testDuplicateMinimizedWindowAnnotatesNativeOpenWindowRowOnly() {
        let element = AXUIElementCreateSystemWide()
        let existing = [
            makeMenuItem(
                "Scan",
                element: element,
                actionKind: .pressMenuItem,
                axIdentifier: " makeKeyAndOrderFront: "
            )
        ]

        let result = WindowSubmenuSynthesis.augmentedItems(
            menuTitle: "Window",
            existingItems: existing,
            synthesizedWindowItems: [makeWindowItem("Scan", markChar: "◆")]
        )

        XCTAssertEqual(result.map(\.title), ["Scan"])
        XCTAssertEqual(result.first?.markChar, "◆")
        XCTAssertEqual(result.first?.actionKind, .pressMenuItem)
        XCTAssertEqual(result.first?.axIdentifier, " makeKeyAndOrderFront: ")
        XCTAssertTrue(result.first?.element.map { CFEqual($0, element) } ?? false)
    }

    func testDuplicateMinimizedWindowDoesNotAnnotateSameTitledCommandRow() {
        let existing = [
            makeMenuItem(
                "Scan",
                actionKind: .pressMenuItem,
                axIdentifier: "_NS:64"
            )
        ]

        let result = WindowSubmenuSynthesis.augmentedItems(
            menuTitle: "Window",
            existingItems: existing,
            synthesizedWindowItems: [makeWindowItem("Scan", markChar: "◆")]
        )

        XCTAssertEqual(result.map(\.title), ["Scan"])
        XCTAssertNil(result.first?.markChar)
        XCTAssertEqual(result.first?.actionKind, .pressMenuItem)
        XCTAssertEqual(result.first?.axIdentifier, "_NS:64")
    }

    func testDuplicateNativeOpenWindowRowClearsStaleDiamondWhenCurrentWindowIsUnmarked() {
        let existing = [
            makeMenuItem(
                "Scan",
                markChar: "◆",
                actionKind: .pressMenuItem,
                axIdentifier: "makeKeyAndOrderFront:"
            )
        ]

        let result = WindowSubmenuSynthesis.augmentedItems(
            menuTitle: "Window",
            existingItems: existing,
            synthesizedWindowItems: [makeWindowItem("Scan", markChar: nil)]
        )

        XCTAssertEqual(result.map(\.title), ["Scan"])
        XCTAssertNil(result.first?.markChar)
        XCTAssertEqual(result.first?.actionKind, .pressMenuItem)
        XCTAssertEqual(result.first?.axIdentifier, "makeKeyAndOrderFront:")
    }

    func testDuplicateNativeOpenWindowRowUsesCurrentSynthesizedCheckmark() {
        let existing = [
            makeMenuItem(
                "Scan",
                markChar: "◆",
                actionKind: .pressMenuItem,
                axIdentifier: "makeKeyAndOrderFront:"
            )
        ]

        let result = WindowSubmenuSynthesis.augmentedItems(
            menuTitle: "Window",
            existingItems: existing,
            synthesizedWindowItems: [makeWindowItem("Scan", markChar: "✓")]
        )

        XCTAssertEqual(result.map(\.title), ["Scan"])
        XCTAssertEqual(result.first?.markChar, "✓")
        XCTAssertEqual(result.first?.actionKind, .pressMenuItem)
        XCTAssertEqual(result.first?.axIdentifier, "makeKeyAndOrderFront:")
    }

    func testNativeOpenWindowRowsMoveCurrentMarkWithoutChangingCommandRows() {
        let existing = [
            makeMenuItem(
                "Scan",
                markChar: "✓",
                actionKind: .pressMenuItem,
                axIdentifier: "makeKeyAndOrderFront:"
            ),
            makeMenuItem(
                "Logs",
                actionKind: .pressMenuItem,
                axIdentifier: "makeKeyAndOrderFront:"
            ),
            makeMenuItem(
                "Logs",
                actionKind: .pressMenuItem,
                axIdentifier: "_NS:59"
            )
        ]

        let result = WindowSubmenuSynthesis.augmentedItems(
            menuTitle: "Window",
            existingItems: existing,
            synthesizedWindowItems: [
                makeWindowItem("Scan", markChar: nil),
                makeWindowItem("Logs", markChar: "✓")
            ]
        )

        XCTAssertEqual(result.map(\.title), ["Scan", "Logs", "Logs"])
        XCTAssertNil(result[0].markChar)
        XCTAssertEqual(result[0].actionKind, .pressMenuItem)
        XCTAssertEqual(result[0].axIdentifier, "makeKeyAndOrderFront:")
        XCTAssertEqual(result[1].markChar, "✓")
        XCTAssertEqual(result[1].actionKind, .pressMenuItem)
        XCTAssertEqual(result[1].axIdentifier, "makeKeyAndOrderFront:")
        XCTAssertNil(result[2].markChar)
        XCTAssertEqual(result[2].axIdentifier, "_NS:59")
    }

    func testNativeOpenWindowRowsReorderByFocusedWindowTabOrderWithinExistingGroup() {
        let existing = [
            makeMenuItem("Minimize"),
            makeSeparator(),
            makeMenuItem("Quote", actionKind: .pressMenuItem, axIdentifier: "makeKeyAndOrderFront:"),
            makeMenuItem("Strict", markChar: "◆", actionKind: .pressMenuItem, axIdentifier: "makeKeyAndOrderFront:"),
            makeMenuItem("Inference", markChar: "✓", actionKind: .pressMenuItem, axIdentifier: "makeKeyAndOrderFront:"),
            makeMenuItem("Bring All to Front", actionKind: .pressMenuItem, axIdentifier: "_NS:27")
        ]

        let result = WindowSubmenuSynthesis.augmentedItems(
            menuTitle: "Window",
            existingItems: existing,
            synthesizedWindowItems: [],
            orderedWindowTitles: ["Inference", "Quote", "Strict"]
        )

        XCTAssertEqual(result.map(\.title), [
            "Minimize", "", "Inference", "Quote", "Strict", "Bring All to Front"
        ])
        XCTAssertEqual(result[2].markChar, "✓")
        XCTAssertEqual(result[2].actionKind, .pressMenuItem)
        XCTAssertEqual(result[2].axIdentifier, "makeKeyAndOrderFront:")
        XCTAssertNil(result[3].markChar)
        XCTAssertEqual(result[4].markChar, "◆")
        XCTAssertEqual(result[5].axIdentifier, "_NS:27")
    }

    func testNativeOpenWindowRowsStayUnchangedWithoutTabOrder() {
        let existing = makeOutOfOrderNativeWindowRows()

        let result = WindowSubmenuSynthesis.augmentedItems(
            menuTitle: "Window",
            existingItems: existing,
            synthesizedWindowItems: [],
            orderedWindowTitles: []
        )

        XCTAssertEqual(result.map(\.title), existing.map(\.title))
    }

    func testNativeOpenWindowRowsStayUnchangedForMissingTabTitle() {
        let existing = makeOutOfOrderNativeWindowRows()

        let result = WindowSubmenuSynthesis.augmentedItems(
            menuTitle: "Window",
            existingItems: existing,
            synthesizedWindowItems: [],
            orderedWindowTitles: ["Inference", "Strict"]
        )

        XCTAssertEqual(result.map(\.title), existing.map(\.title))
    }

    func testNativeOpenWindowRowsStayUnchangedForDuplicateTabTitles() {
        let existing = makeOutOfOrderNativeWindowRows()

        let result = WindowSubmenuSynthesis.augmentedItems(
            menuTitle: "Window",
            existingItems: existing,
            synthesizedWindowItems: [],
            orderedWindowTitles: ["Inference", "Quote", "Quote"]
        )

        XCTAssertEqual(result.map(\.title), existing.map(\.title))
    }

    func testNativeOpenWindowRowsStayUnchangedForDuplicateNativeWindowTitles() {
        let existing = [
            makeMenuItem("Quote", actionKind: .pressMenuItem, axIdentifier: "makeKeyAndOrderFront:"),
            makeMenuItem("Quote", actionKind: .pressMenuItem, axIdentifier: "makeKeyAndOrderFront:"),
            makeMenuItem("Inference", actionKind: .pressMenuItem, axIdentifier: "makeKeyAndOrderFront:")
        ]

        let result = WindowSubmenuSynthesis.augmentedItems(
            menuTitle: "Window",
            existingItems: existing,
            synthesizedWindowItems: [],
            orderedWindowTitles: ["Inference", "Quote"]
        )

        XCTAssertEqual(result.map(\.title), existing.map(\.title))
    }

    private func makeOutOfOrderNativeWindowRows() -> [MenuItem] {
        [
            makeMenuItem("Quote", actionKind: .pressMenuItem, axIdentifier: "makeKeyAndOrderFront:"),
            makeMenuItem("Strict", actionKind: .pressMenuItem, axIdentifier: "makeKeyAndOrderFront:"),
            makeMenuItem("Inference", actionKind: .pressMenuItem, axIdentifier: "makeKeyAndOrderFront:")
        ]
    }

    private func makeMenuItem(
        _ title: String,
        isSeparator: Bool = false,
        markChar: String? = nil,
        element: AXUIElement? = nil,
        actionKind: MenuItemActionKind = .pressMenuItem,
        axIdentifier: String? = nil
    ) -> MenuItem {
        MenuItem(
            title: title,
            isEnabled: !isSeparator,
            hasSubmenu: false,
            isSeparator: isSeparator,
            element: element,
            submenuItems: [],
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

    private func makeWindowItem(_ title: String, markChar: String? = nil) -> MenuItem {
        makeMenuItem(title, markChar: markChar, actionKind: .raiseAXWindow)
    }

    private func makeSeparator() -> MenuItem {
        makeMenuItem("", isSeparator: true)
    }
}
