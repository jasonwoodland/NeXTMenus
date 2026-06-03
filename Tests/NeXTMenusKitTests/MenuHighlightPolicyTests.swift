import XCTest
@testable import NeXTMenusKit

final class MenuHighlightPolicyTests: XCTestCase {
    func testMainPlainHoverWithoutOpenSubmenuStaysUnhighlighted() {
        XCTAssertEqual(main(hoveredRow: 2), appearance(false))
    }

    func testMainOpenChildRowIsHighlighted() {
        XCTAssertEqual(main(childSubmenuRow: 2), appearance(true))
    }

    func testMainSiblingHoverWhileChildOpenIsHighlighted() {
        XCTAssertEqual(main(row: 3, hoveredRow: 3, childSubmenuRow: 2), appearance(true))
    }

    func testMainDragOverRowHighlightsOnlyHoveredRow() {
        XCTAssertEqual(main(row: 3, hoveredRow: 3, childSubmenuRow: 2, isDragging: true), appearance(true))
        XCTAssertEqual(main(row: 2, hoveredRow: 3, childSubmenuRow: 2, isDragging: true), appearance(false))
    }

    func testMainOpenChildRowDeEmphasizesWhenChildHasMouse() {
        XCTAssertEqual(
            main(childSubmenuRow: 2, childHasMouse: true),
            appearance(true, emphasized: false)
        )
    }

    func testMainDragOffRowsKeepsOpenChildHighlightedAndDeEmphasized() {
        XCTAssertEqual(
            main(hoveredRow: -1, childSubmenuRow: 2, isDragging: true),
            appearance(true, emphasized: false)
        )
    }

    func testMainTrailingActionPlainHoverIsUnhighlighted() {
        XCTAssertEqual(main(isTrailingAction: true, hoveredRow: 2), appearance(false))
    }

    func testMainTrailingActionDragHoverUsesDragHighlightRule() {
        XCTAssertEqual(main(isTrailingAction: true, hoveredRow: 2, isDragging: true), appearance(true))
    }

    func testMainTrailingActionPressedIsHighlighted() {
        XCTAssertEqual(main(isTrailingAction: true, hoveredRow: 2, pressedRow: 2), appearance(true))
    }

    func testMainTrailingActionInTrackingModeIsHighlighted() {
        XCTAssertEqual(main(isTrailingAction: true, hoveredRow: 2, isMenuActive: true), appearance(true))
    }

    func testMainFlashOverridesHoverabilityAndNormalState() {
        XCTAssertEqual(main(isHoverable: false, flash: MenuRowFlash(row: 2, isOn: true)), appearance(true))
        XCTAssertEqual(main(childSubmenuRow: 2, flash: MenuRowFlash(row: 2, isOn: false)), appearance(false))
    }

    func testMainNonHoverableRowStaysUnhighlightedWithoutFlash() {
        XCTAssertEqual(main(isHoverable: false, hoveredRow: 2, childSubmenuRow: 2), appearance(false))
    }

    func testSubmenuAttachedHoverIsHighlighted() {
        XCTAssertEqual(submenu(hoveredRow: 2), appearance(true))
    }

    func testSubmenuAttachedChildRowIsHighlighted() {
        XCTAssertEqual(submenu(childSubmenuRow: 2), appearance(true))
    }

    func testSubmenuTornOffLeafHoverIsUnhighlighted() {
        XCTAssertEqual(submenu(isSubmenuRow: false, hoveredRow: 2, isTornOff: true), appearance(false))
    }

    func testSubmenuTornOffOpenChildRowIsHighlighted() {
        XCTAssertEqual(submenu(childSubmenuRow: 2, isTornOff: true), appearance(true))
    }

    func testSubmenuTornOffDragHoverIsHighlighted() {
        XCTAssertEqual(submenu(hoveredRow: 2, isDragging: true, isTornOff: true), appearance(true))
    }

    func testSubmenuTornOffSubmenuRowWhileChildOpenIsHighlighted() {
        XCTAssertEqual(
            submenu(row: 3, isSubmenuRow: true, hoveredRow: 3, childSubmenuRow: 2, isTornOff: true),
            appearance(true)
        )
    }

    func testSubmenuChildPointerDeEmphasizesOpenChildRow() {
        XCTAssertEqual(
            submenu(childSubmenuRow: 2, childHasMouse: true),
            appearance(true, emphasized: false)
        )
    }

    func testSubmenuFlashOverridesHoverabilityAndNormalState() {
        XCTAssertEqual(submenu(isHoverable: false, flash: MenuRowFlash(row: 2, isOn: true)), appearance(true))
        XCTAssertEqual(submenu(childSubmenuRow: 2, flash: MenuRowFlash(row: 2, isOn: false)), appearance(false))
    }

    func testSubmenuNonHoverableRowStaysUnhighlightedWithoutFlash() {
        XCTAssertEqual(submenu(isHoverable: false, hoveredRow: 2, childSubmenuRow: 2), appearance(false))
    }

    private func main(
        row: Int = 2,
        isHoverable: Bool = true,
        isTrailingAction: Bool = false,
        hoveredRow: Int? = nil,
        childSubmenuRow: Int? = nil,
        childHasMouse: Bool = false,
        pressedRow: Int? = nil,
        isDragging: Bool = false,
        isMenuActive: Bool = false,
        flash: MenuRowFlash? = nil
    ) -> MenuRowAppearance {
        MenuHighlightPolicy.mainRowAppearance(
            row: row,
            isHoverable: isHoverable,
            isTrailingAction: isTrailingAction,
            hoveredRow: hoveredRow,
            childSubmenuRow: childSubmenuRow,
            childHasMouse: childHasMouse,
            pressedRow: pressedRow,
            isDragging: isDragging,
            isMenuActive: isMenuActive,
            flash: flash
        )
    }

    private func submenu(
        row: Int = 2,
        isHoverable: Bool = true,
        isSubmenuRow: Bool = true,
        hoveredRow: Int? = nil,
        childSubmenuRow: Int? = nil,
        childHasMouse: Bool = false,
        isDragging: Bool = false,
        isTornOff: Bool = false,
        flash: MenuRowFlash? = nil
    ) -> MenuRowAppearance {
        MenuHighlightPolicy.submenuRowAppearance(
            row: row,
            isHoverable: isHoverable,
            isSubmenuRow: isSubmenuRow,
            hoveredRow: hoveredRow,
            childSubmenuRow: childSubmenuRow,
            childHasMouse: childHasMouse,
            isDragging: isDragging,
            isTornOff: isTornOff,
            flash: flash
        )
    }

    private func appearance(
        _ highlighted: Bool,
        emphasized: Bool = true
    ) -> MenuRowAppearance {
        MenuRowAppearance(isHighlighted: highlighted, isEmphasized: emphasized)
    }
}
