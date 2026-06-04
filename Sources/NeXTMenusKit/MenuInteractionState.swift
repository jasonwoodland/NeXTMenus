import Foundation

public enum MainOpenSubmenuIntent: Equatable {
    case ignore
    case collapse(endsTracking: Bool)
    case showSubmenu(row: Int)
}

public enum SubmenuOpenSubmenuIntent: Equatable {
    case ignore
    case close
    case present(row: Int)
}

public enum MainMouseUpIntent: Equatable {
    case performTrailingAction(row: Int)
    case collapseAndClearHover
    case deactivateAndClearHover
    case hideAttachedCopy
    case toggleClose
    case keepOpenAndRaiseChain
}

public enum SubmenuMouseUpIntent: Equatable {
    case closeChildClearHoverAndDismissChain
    case closeChildClearHover
    case ignore
    case hideAttachedCopy
    case closeTornOffOpenChild
    case keepAttachedOpenChild
    case closeDraggedOpenChild
    case performLeafAction(clearHover: Bool)
}

public enum MainMouseDownAction: Equatable {
    case none
    case updateHighlights
    case showSubmenu(row: Int)
}

public struct MainMouseDownDecision: Equatable {
    public let pressedRow: Int?
    public let pressedRowWasOpen: Bool
    public let pressedDetachedSubmenuRow: Int?
    public let action: MainMouseDownAction

    public init(
        pressedRow: Int?,
        pressedRowWasOpen: Bool,
        pressedDetachedSubmenuRow: Int?,
        action: MainMouseDownAction
    ) {
        self.pressedRow = pressedRow
        self.pressedRowWasOpen = pressedRowWasOpen
        self.pressedDetachedSubmenuRow = pressedDetachedSubmenuRow
        self.action = action
    }
}

public enum SubmenuMouseDownAction: Equatable {
    case none
    case updateTornOffPressHighlight(row: Int)
    case handleSubmenuPress(row: Int, updateTornOffPressHighlight: Bool)
}

public struct SubmenuMouseDownDecision: Equatable {
    public let pressedOpenSubmenuRow: Int?
    public let pressedDetachedSubmenuRow: Int?
    public let action: SubmenuMouseDownAction

    public init(
        pressedOpenSubmenuRow: Int?,
        pressedDetachedSubmenuRow: Int?,
        action: SubmenuMouseDownAction
    ) {
        self.pressedOpenSubmenuRow = pressedOpenSubmenuRow
        self.pressedDetachedSubmenuRow = pressedDetachedSubmenuRow
        self.action = action
    }
}

public enum MainInteractionResetReason: Equatable {
    case collapse(endsTracking: Bool)
    case visibleItemsChanged
    case childTornOff
}

public struct MainInteractionResetPlan: Equatable {
    public let clearChildSubmenu: Bool
    public let clearHoveredRow: Bool
    public let clearDragging: Bool
    public let clearPressedRow: Bool
    public let clearPressedRowWasOpen: Bool
    public let clearPressedDetachedSubmenuRow: Bool
    public let clearChildHasMouse: Bool
    public let deactivateMenu: Bool
    public let clearFlash: Bool
    public let invalidateAsyncSubmenuOpen: Bool

    public init(
        clearChildSubmenu: Bool,
        clearHoveredRow: Bool,
        clearDragging: Bool,
        clearPressedRow: Bool,
        clearPressedRowWasOpen: Bool,
        clearPressedDetachedSubmenuRow: Bool,
        clearChildHasMouse: Bool,
        deactivateMenu: Bool,
        clearFlash: Bool,
        invalidateAsyncSubmenuOpen: Bool
    ) {
        self.clearChildSubmenu = clearChildSubmenu
        self.clearHoveredRow = clearHoveredRow
        self.clearDragging = clearDragging
        self.clearPressedRow = clearPressedRow
        self.clearPressedRowWasOpen = clearPressedRowWasOpen
        self.clearPressedDetachedSubmenuRow = clearPressedDetachedSubmenuRow
        self.clearChildHasMouse = clearChildHasMouse
        self.deactivateMenu = deactivateMenu
        self.clearFlash = clearFlash
        self.invalidateAsyncSubmenuOpen = invalidateAsyncSubmenuOpen
    }
}

public enum SubmenuInteractionResetReason: Equatable {
    case closeChild
    case visibleItemsChanged
    case hideTransientAttachedChild
    case windowWillClose
    case childTornOff
    case hideWindow
}

public struct SubmenuInteractionResetPlan: Equatable {
    public let clearChildSubmenu: Bool
    public let clearHoveredRow: Bool
    public let clearDragging: Bool
    public let clearPressedOpenSubmenuRow: Bool
    public let clearPressedDetachedSubmenuRow: Bool
    public let clearChildHasMouse: Bool
    public let clearFlash: Bool

    public init(
        clearChildSubmenu: Bool,
        clearHoveredRow: Bool,
        clearDragging: Bool,
        clearPressedOpenSubmenuRow: Bool,
        clearPressedDetachedSubmenuRow: Bool,
        clearChildHasMouse: Bool,
        clearFlash: Bool
    ) {
        self.clearChildSubmenu = clearChildSubmenu
        self.clearHoveredRow = clearHoveredRow
        self.clearDragging = clearDragging
        self.clearPressedOpenSubmenuRow = clearPressedOpenSubmenuRow
        self.clearPressedDetachedSubmenuRow = clearPressedDetachedSubmenuRow
        self.clearChildHasMouse = clearChildHasMouse
        self.clearFlash = clearFlash
    }
}

public enum MenuInteractionPolicy {
    public static func mainResetPlan(for reason: MainInteractionResetReason) -> MainInteractionResetPlan {
        switch reason {
        case .collapse(let endsTracking):
            return MainInteractionResetPlan(
                clearChildSubmenu: true,
                clearHoveredRow: true,
                clearDragging: true,
                clearPressedRow: true,
                clearPressedRowWasOpen: true,
                clearPressedDetachedSubmenuRow: true,
                clearChildHasMouse: true,
                deactivateMenu: endsTracking,
                clearFlash: false,
                invalidateAsyncSubmenuOpen: true
            )
        case .visibleItemsChanged:
            return MainInteractionResetPlan(
                clearChildSubmenu: true,
                clearHoveredRow: true,
                clearDragging: true,
                clearPressedRow: true,
                clearPressedRowWasOpen: true,
                clearPressedDetachedSubmenuRow: true,
                clearChildHasMouse: true,
                deactivateMenu: true,
                clearFlash: true,
                invalidateAsyncSubmenuOpen: true
            )
        case .childTornOff:
            return MainInteractionResetPlan(
                clearChildSubmenu: true,
                clearHoveredRow: true,
                clearDragging: true,
                clearPressedRow: true,
                clearPressedRowWasOpen: true,
                clearPressedDetachedSubmenuRow: true,
                clearChildHasMouse: true,
                deactivateMenu: true,
                clearFlash: false,
                invalidateAsyncSubmenuOpen: true
            )
        }
    }

    public static func submenuResetPlan(for reason: SubmenuInteractionResetReason) -> SubmenuInteractionResetPlan {
        switch reason {
        case .closeChild:
            return SubmenuInteractionResetPlan(
                clearChildSubmenu: true,
                clearHoveredRow: false,
                clearDragging: false,
                clearPressedOpenSubmenuRow: true,
                clearPressedDetachedSubmenuRow: true,
                clearChildHasMouse: false,
                clearFlash: false
            )
        case .visibleItemsChanged:
            return SubmenuInteractionResetPlan(
                clearChildSubmenu: true,
                clearHoveredRow: true,
                clearDragging: true,
                clearPressedOpenSubmenuRow: true,
                clearPressedDetachedSubmenuRow: true,
                clearChildHasMouse: true,
                clearFlash: true
            )
        case .hideTransientAttachedChild:
            return SubmenuInteractionResetPlan(
                clearChildSubmenu: true,
                clearHoveredRow: true,
                clearDragging: true,
                clearPressedOpenSubmenuRow: true,
                clearPressedDetachedSubmenuRow: true,
                clearChildHasMouse: true,
                clearFlash: false
            )
        case .windowWillClose:
            return SubmenuInteractionResetPlan(
                clearChildSubmenu: true,
                clearHoveredRow: false,
                clearDragging: false,
                clearPressedOpenSubmenuRow: false,
                clearPressedDetachedSubmenuRow: false,
                clearChildHasMouse: false,
                clearFlash: false
            )
        case .childTornOff:
            return SubmenuInteractionResetPlan(
                clearChildSubmenu: true,
                clearHoveredRow: true,
                clearDragging: true,
                clearPressedOpenSubmenuRow: false,
                clearPressedDetachedSubmenuRow: true,
                clearChildHasMouse: true,
                clearFlash: false
            )
        case .hideWindow:
            return SubmenuInteractionResetPlan(
                clearChildSubmenu: true,
                clearHoveredRow: true,
                clearDragging: false,
                clearPressedOpenSubmenuRow: true,
                clearPressedDetachedSubmenuRow: true,
                clearChildHasMouse: false,
                clearFlash: false
            )
        }
    }

    public static func mainMouseDownDecision(
        row: Int,
        isSelectable: Bool,
        isTrailingAction: Bool,
        childSubmenuRow: Int?,
        hasMenuItem: Bool,
        isSeparator: Bool,
        hasRestorableDetachedSubmenu: Bool
    ) -> MainMouseDownDecision {
        let pressedRow = row >= 0 ? row : nil
        let cleared = MainMouseDownDecision(
            pressedRow: pressedRow,
            pressedRowWasOpen: false,
            pressedDetachedSubmenuRow: nil,
            action: .none
        )

        guard row >= 0 else { return cleared }
        guard isSelectable else { return cleared }

        if isTrailingAction {
            return MainMouseDownDecision(
                pressedRow: pressedRow,
                pressedRowWasOpen: false,
                pressedDetachedSubmenuRow: nil,
                action: .updateHighlights
            )
        }

        if childSubmenuRow == row {
            return MainMouseDownDecision(
                pressedRow: pressedRow,
                pressedRowWasOpen: true,
                pressedDetachedSubmenuRow: nil,
                action: .updateHighlights
            )
        }

        guard hasMenuItem, !isSeparator else { return cleared }

        return MainMouseDownDecision(
            pressedRow: pressedRow,
            pressedRowWasOpen: false,
            pressedDetachedSubmenuRow: hasRestorableDetachedSubmenu ? row : nil,
            action: .showSubmenu(row: row)
        )
    }

    public static func submenuMouseDownDecision(
        row: Int,
        isInBounds: Bool,
        isSelectable: Bool,
        isTornOff: Bool,
        childSubmenuRow: Int?,
        hasSubmenu: Bool,
        hasRestorableDetachedSubmenu: Bool
    ) -> SubmenuMouseDownDecision {
        let cleared = SubmenuMouseDownDecision(
            pressedOpenSubmenuRow: nil,
            pressedDetachedSubmenuRow: nil,
            action: .none
        )

        guard row >= 0, isInBounds, isSelectable else { return cleared }

        guard hasSubmenu else {
            if isTornOff {
                return SubmenuMouseDownDecision(
                    pressedOpenSubmenuRow: nil,
                    pressedDetachedSubmenuRow: nil,
                    action: .updateTornOffPressHighlight(row: row)
                )
            }
            return cleared
        }

        let pressedDetachedSubmenuRow = hasRestorableDetachedSubmenu ? row : nil
        if childSubmenuRow == row {
            return SubmenuMouseDownDecision(
                pressedOpenSubmenuRow: row,
                pressedDetachedSubmenuRow: pressedDetachedSubmenuRow,
                action: isTornOff ? .updateTornOffPressHighlight(row: row) : .none
            )
        }

        return SubmenuMouseDownDecision(
            pressedOpenSubmenuRow: nil,
            pressedDetachedSubmenuRow: pressedDetachedSubmenuRow,
            action: .handleSubmenuPress(row: row, updateTornOffPressHighlight: isTornOff)
        )
    }

    public static func mainOpenSubmenuIntent(
        hoveredRow: Int,
        childSubmenuRow: Int?,
        isInBounds: Bool,
        isSelectable: Bool,
        isTrailingAction: Bool,
        isDragging: Bool,
        hasMenuItem: Bool,
        isSeparator: Bool
    ) -> MainOpenSubmenuIntent {
        guard hoveredRow >= 0 else { return .ignore }
        guard isInBounds else { return .ignore }
        if childSubmenuRow == hoveredRow { return .ignore }
        guard isSelectable else { return .ignore }

        if isTrailingAction {
            guard childSubmenuRow != nil else { return .ignore }
            return .collapse(endsTracking: false)
        }

        if isDragging, childSubmenuRow != nil {
            return .collapse(endsTracking: true)
        }

        guard hasMenuItem, !isSeparator else { return .ignore }
        return .showSubmenu(row: hoveredRow)
    }

    public static func submenuOpenSubmenuIntent(
        hoveredRow: Int,
        childSubmenuRow: Int?,
        isDragging: Bool,
        isInBounds: Bool,
        isSelectable: Bool,
        isSeparator: Bool,
        hasSubmenu: Bool
    ) -> SubmenuOpenSubmenuIntent {
        guard hoveredRow >= 0 else { return .ignore }
        if childSubmenuRow == hoveredRow { return .ignore }

        if isDragging, childSubmenuRow != nil {
            return .close
        }

        if isInBounds, isSelectable, !isSeparator, hasSubmenu {
            return .present(row: hoveredRow)
        }

        guard childSubmenuRow != nil else { return .ignore }
        return .close
    }

    public static func mainMouseUpIntent(
        releasedRow: Int,
        pressedRow: Int?,
        pressedRowWasOpen: Bool,
        pressedDetachedSubmenuRow: Int?,
        childSubmenuRow: Int?,
        wasDragged: Bool,
        isSelectable: Bool,
        hasTrailingAction: Bool
    ) -> MainMouseUpIntent {
        if hasTrailingAction {
            return .performTrailingAction(row: releasedRow)
        }

        guard releasedRow >= 0 else {
            return childSubmenuRow == nil ? .deactivateAndClearHover : .collapseAndClearHover
        }

        guard isSelectable else { return .collapseAndClearHover }

        if shouldHideAttachedCopyOnMouseUp(
            pressedDetachedSubmenuRow: pressedDetachedSubmenuRow,
            releasedRow: releasedRow,
            childSubmenuRow: childSubmenuRow,
            wasDragged: wasDragged
        ) {
            return .hideAttachedCopy
        }

        if !wasDragged, pressedRowWasOpen, pressedRow == releasedRow {
            return .toggleClose
        }

        return .keepOpenAndRaiseChain
    }

    public static func submenuMouseUpIntent(
        releasedRow: Int,
        pressedOpenSubmenuRow: Int?,
        pressedDetachedSubmenuRow: Int?,
        childSubmenuRow: Int?,
        wasDragged: Bool,
        isTornOff: Bool,
        isInBounds: Bool,
        isSelectable: Bool,
        hasSubmenu: Bool,
        hasElement: Bool
    ) -> SubmenuMouseUpIntent {
        guard releasedRow >= 0 else {
            return isTornOff ? .closeChildClearHover : .closeChildClearHoverAndDismissChain
        }

        guard isInBounds else { return .ignore }

        guard isSelectable else {
            return isTornOff ? .closeChildClearHover : .closeChildClearHoverAndDismissChain
        }

        if hasSubmenu {
            if shouldHideAttachedCopyOnMouseUp(
                pressedDetachedSubmenuRow: pressedDetachedSubmenuRow,
                releasedRow: releasedRow,
                childSubmenuRow: childSubmenuRow,
                wasDragged: wasDragged
            ) {
                return .hideAttachedCopy
            }

            if pressedOpenSubmenuRow == releasedRow, childSubmenuRow == releasedRow {
                return isTornOff ? .closeTornOffOpenChild : .keepAttachedOpenChild
            }

            if wasDragged, childSubmenuRow == releasedRow {
                return .closeDraggedOpenChild
            }

            return .ignore
        }

        guard hasElement else { return .ignore }
        return .performLeafAction(clearHover: isTornOff)
    }

    public static func shouldHideAttachedCopyOnMouseUp(
        pressedDetachedSubmenuRow: Int?,
        releasedRow: Int,
        childSubmenuRow: Int?,
        wasDragged: Bool
    ) -> Bool {
        guard !wasDragged else { return false }
        guard pressedDetachedSubmenuRow == releasedRow else { return false }
        guard childSubmenuRow == releasedRow else { return false }
        return true
    }
}
