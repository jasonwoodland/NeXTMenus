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

    func testAttachedCopyMouseUpHidesOnlyWhenPressedDetachedReleasedAndChildRowsMatch() {
        XCTAssertTrue(
            MenuInteractionPolicy.shouldHideAttachedCopyOnMouseUp(
                pressedDetachedSubmenuRow: 3,
                releasedRow: 3,
                childSubmenuRow: 3,
                wasDragged: false
            )
        )
    }

    func testAttachedCopyMouseUpDoesNotHideForDragRelease() {
        XCTAssertFalse(
            MenuInteractionPolicy.shouldHideAttachedCopyOnMouseUp(
                pressedDetachedSubmenuRow: 3,
                releasedRow: 3,
                childSubmenuRow: 3,
                wasDragged: true
            )
        )
    }

    func testAttachedCopyMouseUpDoesNotHideForMismatchedReleaseRow() {
        XCTAssertFalse(
            MenuInteractionPolicy.shouldHideAttachedCopyOnMouseUp(
                pressedDetachedSubmenuRow: 3,
                releasedRow: 4,
                childSubmenuRow: 3,
                wasDragged: false
            )
        )
    }

    func testAttachedCopyMouseUpDoesNotHideForMismatchedChildRow() {
        XCTAssertFalse(
            MenuInteractionPolicy.shouldHideAttachedCopyOnMouseUp(
                pressedDetachedSubmenuRow: 3,
                releasedRow: 3,
                childSubmenuRow: 4,
                wasDragged: false
            )
        )
    }

    func testAttachedCopyMouseUpDoesNotHideWithoutTemporaryAttachedChild() {
        XCTAssertFalse(
            MenuInteractionPolicy.shouldHideAttachedCopyOnMouseUp(
                pressedDetachedSubmenuRow: 3,
                releasedRow: 3,
                childSubmenuRow: nil,
                wasDragged: false
            )
        )
    }

    func testAttachedCopyMouseUpDoesNotHideWithoutPressedDetachedRow() {
        XCTAssertFalse(
            MenuInteractionPolicy.shouldHideAttachedCopyOnMouseUp(
                pressedDetachedSubmenuRow: nil,
                releasedRow: 3,
                childSubmenuRow: 3,
                wasDragged: false
            )
        )
    }

    func testMainMouseUpTrailingActionPerformsBeforeOtherBranches() {
        XCTAssertEqual(mainMouseUp(releasedRow: 9, hasTrailingAction: true), .performTrailingAction(row: 9))
    }

    func testMainMouseUpOffRowCollapsesWhenChildOpen() {
        XCTAssertEqual(mainMouseUp(releasedRow: -1, childSubmenuRow: 2), .collapseAndClearHover)
    }

    func testMainMouseUpOffRowDeactivatesWhenNoChildOpen() {
        XCTAssertEqual(mainMouseUp(releasedRow: -1), .deactivateAndClearHover)
    }

    func testMainMouseUpNonSelectableOrHighOutOfBoundsCollapses() {
        XCTAssertEqual(mainMouseUp(releasedRow: 3, isSelectable: false), .collapseAndClearHover)
        XCTAssertEqual(mainMouseUp(releasedRow: 99, isSelectable: false), .collapseAndClearHover)
    }

    func testMainMouseUpMatchingDetachedCopyHidesAttachedCopy() {
        XCTAssertEqual(
            mainMouseUp(
                releasedRow: 3,
                pressedDetachedSubmenuRow: 3,
                childSubmenuRow: 3
            ),
            .hideAttachedCopy
        )
    }

    func testMainMouseUpDetachedCopyDoesNotHideForDragOrMismatch() {
        XCTAssertEqual(
            mainMouseUp(
                releasedRow: 3,
                pressedDetachedSubmenuRow: 3,
                childSubmenuRow: 3,
                wasDragged: true
            ),
            .keepOpenAndRaiseChain
        )
        XCTAssertEqual(
            mainMouseUp(
                releasedRow: 4,
                pressedDetachedSubmenuRow: 3,
                childSubmenuRow: 3
            ),
            .keepOpenAndRaiseChain
        )
        XCTAssertEqual(
            mainMouseUp(
                releasedRow: 3,
                pressedDetachedSubmenuRow: 3,
                childSubmenuRow: 4
            ),
            .keepOpenAndRaiseChain
        )
    }

    func testMainMouseUpToggleCloseOnlyForMatchingUndraggedOpenPress() {
        XCTAssertEqual(
            mainMouseUp(releasedRow: 3, pressedRow: 3, pressedRowWasOpen: true),
            .toggleClose
        )
        XCTAssertEqual(
            mainMouseUp(releasedRow: 3, pressedRow: 3, pressedRowWasOpen: true, wasDragged: true),
            .keepOpenAndRaiseChain
        )
        XCTAssertEqual(
            mainMouseUp(releasedRow: 4, pressedRow: 3, pressedRowWasOpen: true),
            .keepOpenAndRaiseChain
        )
    }

    func testMainMouseUpNormalReleaseKeepsOpenAndRaisesChain() {
        XCTAssertEqual(mainMouseUp(releasedRow: 3), .keepOpenAndRaiseChain)
    }

    func testSubmenuMouseUpOffRowAttachedDismissesChain() {
        XCTAssertEqual(submenuMouseUp(releasedRow: -1, isTornOff: false), .closeChildClearHoverAndDismissChain)
    }

    func testSubmenuMouseUpOffRowTornOffKeepsChainVisible() {
        XCTAssertEqual(submenuMouseUp(releasedRow: -1, isTornOff: true), .closeChildClearHover)
    }

    func testSubmenuMouseUpHighOutOfBoundsIgnores() {
        XCTAssertEqual(submenuMouseUp(releasedRow: 99, isInBounds: false), .ignore)
    }

    func testSubmenuMouseUpNonSelectableAttachedDismissesChain() {
        XCTAssertEqual(
            submenuMouseUp(releasedRow: 3, isTornOff: false, isSelectable: false),
            .closeChildClearHoverAndDismissChain
        )
    }

    func testSubmenuMouseUpNonSelectableTornOffKeepsChainVisible() {
        XCTAssertEqual(
            submenuMouseUp(releasedRow: 3, isTornOff: true, isSelectable: false),
            .closeChildClearHover
        )
    }

    func testSubmenuMouseUpMatchingDetachedCopyHidesAttachedCopy() {
        XCTAssertEqual(
            submenuMouseUp(
                releasedRow: 3,
                pressedDetachedSubmenuRow: 3,
                childSubmenuRow: 3,
                hasSubmenu: true
            ),
            .hideAttachedCopy
        )
    }

    func testSubmenuMouseUpPressedOpenChildTakesPrecedenceOverDraggedRelease() {
        XCTAssertEqual(
            submenuMouseUp(
                releasedRow: 3,
                pressedOpenSubmenuRow: 3,
                childSubmenuRow: 3,
                wasDragged: true,
                isTornOff: false,
                hasSubmenu: true
            ),
            .keepAttachedOpenChild
        )
        XCTAssertEqual(
            submenuMouseUp(
                releasedRow: 3,
                pressedOpenSubmenuRow: 3,
                childSubmenuRow: 3,
                wasDragged: true,
                isTornOff: true,
                hasSubmenu: true
            ),
            .closeTornOffOpenChild
        )
    }

    func testSubmenuMouseUpDraggedReleaseOnOpenChildClosesWithoutPressedOpenMatch() {
        XCTAssertEqual(
            submenuMouseUp(
                releasedRow: 3,
                pressedOpenSubmenuRow: nil,
                childSubmenuRow: 3,
                wasDragged: true,
                hasSubmenu: true
            ),
            .closeDraggedOpenChild
        )
        XCTAssertEqual(
            submenuMouseUp(
                releasedRow: 3,
                pressedOpenSubmenuRow: 2,
                childSubmenuRow: 3,
                wasDragged: true,
                hasSubmenu: true
            ),
            .closeDraggedOpenChild
        )
    }

    func testSubmenuMouseUpSubmenuCapableRowOtherwiseIgnores() {
        XCTAssertEqual(submenuMouseUp(releasedRow: 3, hasSubmenu: true), .ignore)
    }

    func testSubmenuMouseUpLeafWithoutElementIgnores() {
        XCTAssertEqual(submenuMouseUp(releasedRow: 3, hasSubmenu: false, hasElement: false), .ignore)
    }

    func testSubmenuMouseUpLeafWithElementPerformsAction() {
        XCTAssertEqual(
            submenuMouseUp(releasedRow: 3, isTornOff: false, hasSubmenu: false, hasElement: true),
            .performLeafAction(clearHover: false)
        )
        XCTAssertEqual(
            submenuMouseUp(releasedRow: 3, isTornOff: true, hasSubmenu: false, hasElement: true),
            .performLeafAction(clearHover: true)
        )
    }

    func testMainMouseDownOffRowClearsPressState() {
        XCTAssertEqual(
            mainMouseDown(row: -1),
            MainMouseDownDecision(
                pressedRow: nil,
                pressedRowWasOpen: false,
                pressedDetachedSubmenuRow: nil,
                action: .none
            )
        )
    }

    func testMainMouseDownNonSelectablePreservesPressedRowOnly() {
        XCTAssertEqual(
            mainMouseDown(row: 3, isSelectable: false, hasRestorableDetachedSubmenu: true),
            MainMouseDownDecision(
                pressedRow: 3,
                pressedRowWasOpen: false,
                pressedDetachedSubmenuRow: nil,
                action: .none
            )
        )
    }

    func testMainMouseDownTrailingActionUpdatesHighlightsOnly() {
        XCTAssertEqual(
            mainMouseDown(row: 7, isTrailingAction: true, hasRestorableDetachedSubmenu: true),
            MainMouseDownDecision(
                pressedRow: 7,
                pressedRowWasOpen: false,
                pressedDetachedSubmenuRow: nil,
                action: .updateHighlights
            )
        )
    }

    func testMainMouseDownAlreadyOpenMarksOpenAndIgnoresDetached() {
        XCTAssertEqual(
            mainMouseDown(row: 3, childSubmenuRow: 3, hasRestorableDetachedSubmenu: true),
            MainMouseDownDecision(
                pressedRow: 3,
                pressedRowWasOpen: true,
                pressedDetachedSubmenuRow: nil,
                action: .updateHighlights
            )
        )
    }

    func testMainMouseDownMissingOrSeparatorRowsDoNotShowSubmenu() {
        XCTAssertEqual(
            mainMouseDown(row: 3, hasMenuItem: false, hasRestorableDetachedSubmenu: true),
            MainMouseDownDecision(
                pressedRow: 3,
                pressedRowWasOpen: false,
                pressedDetachedSubmenuRow: nil,
                action: .none
            )
        )
        XCTAssertEqual(
            mainMouseDown(row: 3, isSeparator: true, hasRestorableDetachedSubmenu: true),
            MainMouseDownDecision(
                pressedRow: 3,
                pressedRowWasOpen: false,
                pressedDetachedSubmenuRow: nil,
                action: .none
            )
        )
    }

    func testMainMouseDownNormalRowsShowSubmenuAndRecordDetached() {
        XCTAssertEqual(
            mainMouseDown(row: 3),
            MainMouseDownDecision(
                pressedRow: 3,
                pressedRowWasOpen: false,
                pressedDetachedSubmenuRow: nil,
                action: .showSubmenu(row: 3)
            )
        )
        XCTAssertEqual(
            mainMouseDown(row: 3, hasRestorableDetachedSubmenu: true),
            MainMouseDownDecision(
                pressedRow: 3,
                pressedRowWasOpen: false,
                pressedDetachedSubmenuRow: 3,
                action: .showSubmenu(row: 3)
            )
        )
    }

    func testSubmenuMouseDownInvalidRowsClearPressStateOnly() {
        XCTAssertEqual(
            submenuMouseDown(row: -1, isInBounds: false, hasRestorableDetachedSubmenu: true),
            SubmenuMouseDownDecision(
                pressedOpenSubmenuRow: nil,
                pressedDetachedSubmenuRow: nil,
                action: .none
            )
        )
        XCTAssertEqual(
            submenuMouseDown(row: 99, isInBounds: false, hasRestorableDetachedSubmenu: true),
            SubmenuMouseDownDecision(
                pressedOpenSubmenuRow: nil,
                pressedDetachedSubmenuRow: nil,
                action: .none
            )
        )
    }

    func testSubmenuMouseDownNonSelectableOrLeafRowsIgnoreDetached() {
        XCTAssertEqual(
            submenuMouseDown(row: 3, isSelectable: false, hasSubmenu: true, hasRestorableDetachedSubmenu: true),
            SubmenuMouseDownDecision(
                pressedOpenSubmenuRow: nil,
                pressedDetachedSubmenuRow: nil,
                action: .none
            )
        )
        XCTAssertEqual(
            submenuMouseDown(row: 3, isTornOff: false, hasSubmenu: false, hasRestorableDetachedSubmenu: true),
            SubmenuMouseDownDecision(
                pressedOpenSubmenuRow: nil,
                pressedDetachedSubmenuRow: nil,
                action: .none
            )
        )
    }

    func testSubmenuMouseDownTornOffLeafUpdatesPressHighlight() {
        XCTAssertEqual(
            submenuMouseDown(row: 3, isTornOff: true, hasSubmenu: false, hasRestorableDetachedSubmenu: true),
            SubmenuMouseDownDecision(
                pressedOpenSubmenuRow: nil,
                pressedDetachedSubmenuRow: nil,
                action: .updateTornOffPressHighlight(row: 3)
            )
        )
    }

    func testSubmenuMouseDownSubmenuRowsHandlePressAndDetachedState() {
        XCTAssertEqual(
            submenuMouseDown(row: 3, isTornOff: false, hasSubmenu: true),
            SubmenuMouseDownDecision(
                pressedOpenSubmenuRow: nil,
                pressedDetachedSubmenuRow: nil,
                action: .handleSubmenuPress(row: 3, updateTornOffPressHighlight: false)
            )
        )
        XCTAssertEqual(
            submenuMouseDown(row: 3, isTornOff: true, hasSubmenu: true),
            SubmenuMouseDownDecision(
                pressedOpenSubmenuRow: nil,
                pressedDetachedSubmenuRow: nil,
                action: .handleSubmenuPress(row: 3, updateTornOffPressHighlight: true)
            )
        )
        XCTAssertEqual(
            submenuMouseDown(row: 3, hasSubmenu: true, hasRestorableDetachedSubmenu: true),
            SubmenuMouseDownDecision(
                pressedOpenSubmenuRow: nil,
                pressedDetachedSubmenuRow: 3,
                action: .handleSubmenuPress(row: 3, updateTornOffPressHighlight: false)
            )
        )
    }

    func testSubmenuMouseDownAlreadyOpenRowsPreserveAttachedAndTornOffDifferences() {
        XCTAssertEqual(
            submenuMouseDown(row: 3, isTornOff: false, childSubmenuRow: 3, hasSubmenu: true),
            SubmenuMouseDownDecision(
                pressedOpenSubmenuRow: 3,
                pressedDetachedSubmenuRow: nil,
                action: .none
            )
        )
        XCTAssertEqual(
            submenuMouseDown(row: 3, isTornOff: true, childSubmenuRow: 3, hasSubmenu: true),
            SubmenuMouseDownDecision(
                pressedOpenSubmenuRow: 3,
                pressedDetachedSubmenuRow: nil,
                action: .updateTornOffPressHighlight(row: 3)
            )
        )
    }

    func testSubmenuMouseDownDetachedAlreadyOpenRecordsBothStates() {
        XCTAssertEqual(
            submenuMouseDown(
                row: 3,
                childSubmenuRow: 3,
                hasSubmenu: true,
                hasRestorableDetachedSubmenu: true
            ),
            SubmenuMouseDownDecision(
                pressedOpenSubmenuRow: 3,
                pressedDetachedSubmenuRow: 3,
                action: .none
            )
        )
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

    private func mainMouseUp(
        releasedRow: Int,
        pressedRow: Int? = nil,
        pressedRowWasOpen: Bool = false,
        pressedDetachedSubmenuRow: Int? = nil,
        childSubmenuRow: Int? = nil,
        wasDragged: Bool = false,
        isSelectable: Bool = true,
        hasTrailingAction: Bool = false
    ) -> MainMouseUpIntent {
        MenuInteractionPolicy.mainMouseUpIntent(
            releasedRow: releasedRow,
            pressedRow: pressedRow,
            pressedRowWasOpen: pressedRowWasOpen,
            pressedDetachedSubmenuRow: pressedDetachedSubmenuRow,
            childSubmenuRow: childSubmenuRow,
            wasDragged: wasDragged,
            isSelectable: isSelectable,
            hasTrailingAction: hasTrailingAction
        )
    }

    private func submenuMouseUp(
        releasedRow: Int,
        pressedOpenSubmenuRow: Int? = nil,
        pressedDetachedSubmenuRow: Int? = nil,
        childSubmenuRow: Int? = nil,
        wasDragged: Bool = false,
        isTornOff: Bool = false,
        isInBounds: Bool = true,
        isSelectable: Bool = true,
        hasSubmenu: Bool = false,
        hasElement: Bool = false
    ) -> SubmenuMouseUpIntent {
        MenuInteractionPolicy.submenuMouseUpIntent(
            releasedRow: releasedRow,
            pressedOpenSubmenuRow: pressedOpenSubmenuRow,
            pressedDetachedSubmenuRow: pressedDetachedSubmenuRow,
            childSubmenuRow: childSubmenuRow,
            wasDragged: wasDragged,
            isTornOff: isTornOff,
            isInBounds: isInBounds,
            isSelectable: isSelectable,
            hasSubmenu: hasSubmenu,
            hasElement: hasElement
        )
    }

    private func mainMouseDown(
        row: Int,
        isSelectable: Bool = true,
        isTrailingAction: Bool = false,
        childSubmenuRow: Int? = nil,
        hasMenuItem: Bool = true,
        isSeparator: Bool = false,
        hasRestorableDetachedSubmenu: Bool = false
    ) -> MainMouseDownDecision {
        MenuInteractionPolicy.mainMouseDownDecision(
            row: row,
            isSelectable: isSelectable,
            isTrailingAction: isTrailingAction,
            childSubmenuRow: childSubmenuRow,
            hasMenuItem: hasMenuItem,
            isSeparator: isSeparator,
            hasRestorableDetachedSubmenu: hasRestorableDetachedSubmenu
        )
    }

    private func submenuMouseDown(
        row: Int,
        isInBounds: Bool = true,
        isSelectable: Bool = true,
        isTornOff: Bool = false,
        childSubmenuRow: Int? = nil,
        hasSubmenu: Bool = false,
        hasRestorableDetachedSubmenu: Bool = false
    ) -> SubmenuMouseDownDecision {
        MenuInteractionPolicy.submenuMouseDownDecision(
            row: row,
            isInBounds: isInBounds,
            isSelectable: isSelectable,
            isTornOff: isTornOff,
            childSubmenuRow: childSubmenuRow,
            hasSubmenu: hasSubmenu,
            hasRestorableDetachedSubmenu: hasRestorableDetachedSubmenu
        )
    }
}
