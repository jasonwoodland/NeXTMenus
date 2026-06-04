import XCTest
@testable import NeXTMenusKit

final class MenuInteractionStateTests: XCTestCase {
    func testMainOffRowHoverIgnoresAndPreservesOpenSubmenu() {
        XCTAssertEqual(main(hoveredRow: -1, childSubmenuRow: 2), .ignore)
    }

    func testMainHighOutOfBoundsRowIgnoresAndPreservesOpenSubmenu() {
        XCTAssertEqual(main(hoveredRow: 99, childSubmenuRow: 2, isInBounds: false), .ignore)
    }

    func testMainAlreadyOpenChildRowIgnoresEvenWhileDragging() {
        XCTAssertEqual(main(hoveredRow: 2, childSubmenuRow: 2, isDragging: true), .ignore)
    }

    func testMainNonSelectableRowIgnores() {
        XCTAssertEqual(main(hoveredRow: 2, isSelectable: false), .ignore)
    }

    func testMainTrailingActionWithOpenChildCollapsesWithoutEndingTracking() {
        XCTAssertEqual(
            main(hoveredRow: 4, childSubmenuRow: 2, isTrailingAction: true),
            .collapse(endsTracking: false)
        )
    }

    func testMainTrailingActionWithOpenChildWhileDraggingStillPreservesTracking() {
        XCTAssertEqual(
            main(hoveredRow: 4, childSubmenuRow: 2, isTrailingAction: true, isDragging: true),
            .collapse(endsTracking: false)
        )
    }

    func testMainTrailingActionWithoutOpenChildIgnores() {
        XCTAssertEqual(main(hoveredRow: 4, isTrailingAction: true), .ignore)
    }

    func testMainDraggingWithOpenChildOverSiblingCollapsesAndEndsTracking() {
        XCTAssertEqual(
            main(hoveredRow: 3, childSubmenuRow: 2, isDragging: true),
            .collapse(endsTracking: true)
        )
    }

    func testMainDraggingWithNoOpenChildOverNormalRowShowsSubmenu() {
        XCTAssertEqual(main(hoveredRow: 3, isDragging: true), .showSubmenu(row: 3))
    }

    func testMainSelectableNormalRowWithMenuItemShowsSubmenu() {
        XCTAssertEqual(main(hoveredRow: 3), .showSubmenu(row: 3))
    }

    func testMainSeparatorOrMissingMenuItemIgnores() {
        XCTAssertEqual(main(hoveredRow: 3, isSeparator: true), .ignore)
        XCTAssertEqual(main(hoveredRow: 3, hasMenuItem: false), .ignore)
    }

    func testMainUsesHasMenuItemRatherThanHasSubmenu() {
        XCTAssertEqual(main(hoveredRow: 3, hasMenuItem: true), .showSubmenu(row: 3))
    }

    func testSubmenuOffRowHoverIgnoresAndPreservesOpenSubmenu() {
        XCTAssertEqual(submenu(hoveredRow: -1, childSubmenuRow: 2), .ignore)
    }

    func testSubmenuAlreadyOpenChildRowIgnoresEvenWhileDragging() {
        XCTAssertEqual(submenu(hoveredRow: 2, childSubmenuRow: 2, isDragging: true), .ignore)
    }

    func testSubmenuDraggingWithOpenChildOverSiblingClosesOnlyCurrentChild() {
        XCTAssertEqual(submenu(hoveredRow: 3, childSubmenuRow: 2, isDragging: true), .close)
    }

    func testSubmenuDraggingWithNoOpenChildOverSubmenuRowPresents() {
        XCTAssertEqual(submenu(hoveredRow: 3, isDragging: true), .present(row: 3))
    }

    func testSubmenuSelectableInBoundsSubmenuRowPresents() {
        XCTAssertEqual(submenu(hoveredRow: 3), .present(row: 3))
    }

    func testSubmenuLeafRowWithOpenChildCloses() {
        XCTAssertEqual(submenu(hoveredRow: 3, childSubmenuRow: 2, hasSubmenu: false), .close)
    }

    func testSubmenuLeafRowWithoutOpenChildIgnores() {
        XCTAssertEqual(submenu(hoveredRow: 3, hasSubmenu: false), .ignore)
    }

    func testSubmenuInvalidRowsWithOpenChildCloseWithoutIndexing() {
        XCTAssertEqual(submenu(hoveredRow: 99, childSubmenuRow: 2, isInBounds: false), .close)
        XCTAssertEqual(submenu(hoveredRow: 3, childSubmenuRow: 2, isSelectable: false), .close)
        XCTAssertEqual(submenu(hoveredRow: 3, childSubmenuRow: 2, isSeparator: true), .close)
    }

    func testSubmenuInvalidRowsWithoutOpenChildIgnoreWithoutIndexing() {
        XCTAssertEqual(submenu(hoveredRow: 99, isInBounds: false), .ignore)
        XCTAssertEqual(submenu(hoveredRow: 3, isSelectable: false), .ignore)
        XCTAssertEqual(submenu(hoveredRow: 3, isSeparator: true), .ignore)
    }

    private func main(
        hoveredRow: Int,
        childSubmenuRow: Int? = nil,
        isInBounds: Bool = true,
        isSelectable: Bool = true,
        isTrailingAction: Bool = false,
        isDragging: Bool = false,
        hasMenuItem: Bool = true,
        isSeparator: Bool = false
    ) -> MainOpenSubmenuIntent {
        MenuInteractionPolicy.mainOpenSubmenuIntent(
            hoveredRow: hoveredRow,
            childSubmenuRow: childSubmenuRow,
            isInBounds: isInBounds,
            isSelectable: isSelectable,
            isTrailingAction: isTrailingAction,
            isDragging: isDragging,
            hasMenuItem: hasMenuItem,
            isSeparator: isSeparator
        )
    }

    private func submenu(
        hoveredRow: Int,
        childSubmenuRow: Int? = nil,
        isDragging: Bool = false,
        isInBounds: Bool = true,
        isSelectable: Bool = true,
        isSeparator: Bool = false,
        hasSubmenu: Bool = true
    ) -> SubmenuOpenSubmenuIntent {
        MenuInteractionPolicy.submenuOpenSubmenuIntent(
            hoveredRow: hoveredRow,
            childSubmenuRow: childSubmenuRow,
            isDragging: isDragging,
            isInBounds: isInBounds,
            isSelectable: isSelectable,
            isSeparator: isSeparator,
            hasSubmenu: hasSubmenu
        )
    }
}
