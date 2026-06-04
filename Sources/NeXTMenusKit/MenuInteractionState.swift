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

public enum MenuInteractionPolicy {
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
