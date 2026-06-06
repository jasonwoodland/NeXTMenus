import XCTest
@testable import NeXTMenusKit

final class TornOffMenuMarkPolicyTests: XCTestCase {
    func testSameIdentifierGroupChecksClickedRowAndClearsSibling() {
        let items = [
            makeItem("Scan", markChar: "✓", axIdentifier: "makeKeyAndOrderFront:"),
            makeItem("Wireless Diagnostics", axIdentifier: "makeKeyAndOrderFront:")
        ]

        let result = TornOffMenuMarkPolicy.optimisticUpdate(
            items: items,
            clickedIndex: 1,
            isKnownCheckable: false
        )

        XCTAssertTrue(result.handled)
        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.items.map(\.markChar), [nil, "✓"])
    }

    func testSameIdentifierGroupWorksInReverseDirection() {
        let items = [
            makeItem("Scan", axIdentifier: "makeKeyAndOrderFront:"),
            makeItem("Wireless Diagnostics", markChar: "✓", axIdentifier: "makeKeyAndOrderFront:")
        ]

        let result = TornOffMenuMarkPolicy.optimisticUpdate(
            items: items,
            clickedIndex: 0,
            isKnownCheckable: false
        )

        XCTAssertTrue(result.handled)
        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.items.map(\.markChar), ["✓", nil])
    }

    func testAlreadyCheckedSameIdentifierGroupRowStaysChecked() {
        let items = [
            makeItem("Scan", markChar: "✓", axIdentifier: "makeKeyAndOrderFront:"),
            makeItem("Wireless Diagnostics", axIdentifier: "makeKeyAndOrderFront:")
        ]

        let result = TornOffMenuMarkPolicy.optimisticUpdate(
            items: items,
            clickedIndex: 0,
            isKnownCheckable: false
        )

        XCTAssertTrue(result.handled)
        XCTAssertFalse(result.changed)
        XCTAssertEqual(result.items.map(\.markChar), ["✓", nil])
    }

    func testSameIdentifierGroupPreservesMinimizedSiblingDiamondWhenMovingCheckmark() {
        let items = [
            makeItem("Scan", markChar: "✓", axIdentifier: "makeKeyAndOrderFront:"),
            makeItem("Wireless Diagnostics", markChar: "◆", axIdentifier: "makeKeyAndOrderFront:"),
            makeItem("Console", axIdentifier: "makeKeyAndOrderFront:")
        ]

        let result = TornOffMenuMarkPolicy.optimisticUpdate(
            items: items,
            clickedIndex: 2,
            isKnownCheckable: false
        )

        XCTAssertTrue(result.handled)
        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.items.map(\.markChar), [nil, "◆", "✓"])
    }

    func testSameIdentifierGroupClickingMinimizedRowReplacesDiamondWithCheckmarkAndClearsCheckedSibling() {
        let items = [
            makeItem("Scan", markChar: "✓", axIdentifier: "makeKeyAndOrderFront:"),
            makeItem("Wireless Diagnostics", markChar: "◆", axIdentifier: "makeKeyAndOrderFront:"),
            makeItem("Console", markChar: "◆", axIdentifier: "makeKeyAndOrderFront:")
        ]

        let result = TornOffMenuMarkPolicy.optimisticUpdate(
            items: items,
            clickedIndex: 1,
            isKnownCheckable: false
        )

        XCTAssertTrue(result.handled)
        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.items.map(\.markChar), [nil, "✓", "◆"])
    }

    func testSingletonMinimizedDiamondIsUnhandledSoControllerCanRefreshAfterAction() {
        let items = [makeItem("Scan", markChar: "◆", axIdentifier: "makeKeyAndOrderFront:")]

        let result = TornOffMenuMarkPolicy.optimisticUpdate(
            items: items,
            clickedIndex: 0,
            isKnownCheckable: true
        )

        XCTAssertFalse(result.handled)
        XCTAssertFalse(result.changed)
        XCTAssertEqual(result.items.map(\.markChar), ["◆"])
    }

    func testIdentifierMatchingTrimsWhitespace() {
        let items = [
            makeItem("Scan", markChar: "✓", axIdentifier: " makeKeyAndOrderFront: "),
            makeItem("Wireless Diagnostics", axIdentifier: "makeKeyAndOrderFront:")
        ]

        let result = TornOffMenuMarkPolicy.optimisticUpdate(
            items: items,
            clickedIndex: 1,
            isKnownCheckable: false
        )

        XCTAssertTrue(result.handled)
        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.items.map(\.markChar), [nil, "✓"])
    }

    func testDifferentIdentifiersUseLegacyToggleAndDoNotClearSibling() {
        let items = [
            makeItem("One", markChar: "✓", axIdentifier: "one:"),
            makeItem("Two", axIdentifier: "two:")
        ]

        let result = TornOffMenuMarkPolicy.optimisticUpdate(
            items: items,
            clickedIndex: 1,
            isKnownCheckable: true
        )

        XCTAssertTrue(result.handled)
        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.items.map(\.markChar), ["✓", "✓"])
    }

    func testEmptyIdentifierUsesLegacyToggleBehavior() {
        let items = [
            makeItem("One", markChar: "✓", axIdentifier: "   "),
            makeItem("Two", axIdentifier: "   ")
        ]

        let result = TornOffMenuMarkPolicy.optimisticUpdate(
            items: items,
            clickedIndex: 0,
            isKnownCheckable: true
        )

        XCTAssertTrue(result.handled)
        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.items.map(\.markChar), [nil, nil])
    }

    func testSingletonIdentifierUsesLegacyToggleBehavior() {
        let items = [makeItem("Scan", markChar: "✓", axIdentifier: "makeKeyAndOrderFront:")]

        let result = TornOffMenuMarkPolicy.optimisticUpdate(
            items: items,
            clickedIndex: 0,
            isKnownCheckable: true
        )

        XCTAssertTrue(result.handled)
        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.items.map(\.markChar), [nil])
    }

    func testUnmarkedUnknownNonRadioRowIsUnhandled() {
        let items = [makeItem("Plain")]

        let result = TornOffMenuMarkPolicy.optimisticUpdate(
            items: items,
            clickedIndex: 0,
            isKnownCheckable: false
        )

        XCTAssertFalse(result.handled)
        XCTAssertFalse(result.changed)
        XCTAssertEqual(result.items.map(\.markChar), [nil])
    }

    private func makeItem(
        _ title: String,
        markChar: String? = nil,
        axIdentifier: String? = nil
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
            markChar: markChar,
            cmdChar: nil,
            cmdModifiers: nil,
            axIdentifier: axIdentifier
        )
    }
}
