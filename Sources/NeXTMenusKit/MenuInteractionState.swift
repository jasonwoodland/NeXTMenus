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
