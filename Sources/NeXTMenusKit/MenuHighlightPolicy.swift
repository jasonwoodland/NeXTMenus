import Foundation

public struct MenuRowAppearance: Equatable {
    public let isHighlighted: Bool
    public let isEmphasized: Bool

    public init(isHighlighted: Bool, isEmphasized: Bool) {
        self.isHighlighted = isHighlighted
        self.isEmphasized = isEmphasized
    }
}

public struct MenuRowFlash: Equatable {
    public let row: Int
    public let isOn: Bool

    public init(row: Int, isOn: Bool) {
        self.row = row
        self.isOn = isOn
    }
}

public enum MenuHighlightPolicy {
    public static func mainRowAppearance(
        row: Int,
        isHoverable: Bool,
        isTrailingAction: Bool,
        hoveredRow: Int?,
        childSubmenuRow: Int?,
        childHasMouse: Bool,
        pressedRow: Int?,
        isDragging: Bool,
        isMenuActive: Bool,
        flash: MenuRowFlash?
    ) -> MenuRowAppearance {
        let isHighlighted: Bool
        if let flash, flash.row == row {
            isHighlighted = flash.isOn
        } else if isDragging {
            let pointerIsOffMainRows = (hoveredRow ?? -1) < 0
            isHighlighted = isHoverable
                && (hoveredRow == row || (pointerIsOffMainRows && childSubmenuRow == row))
        } else if isTrailingAction {
            isHighlighted = isHoverable
                && hoveredRow == row
                && (pressedRow == row || isMenuActive)
        } else {
            isHighlighted = isHoverable
                && (childSubmenuRow == row || (hoveredRow == row && childSubmenuRow != nil))
        }

        let pointerIsOffMainRows = (hoveredRow ?? -1) < 0
        let deEmphasizeOpenSubmenu = (childSubmenuRow == row)
            && (childHasMouse || (isDragging && pointerIsOffMainRows))

        return MenuRowAppearance(
            isHighlighted: isHighlighted,
            isEmphasized: !deEmphasizeOpenSubmenu
        )
    }

    public static func submenuRowAppearance(
        row: Int,
        isHoverable: Bool,
        isSubmenuRow: Bool,
        hoveredRow: Int?,
        childSubmenuRow: Int?,
        childHasMouse: Bool,
        isDragging: Bool,
        isTornOff: Bool,
        flash: MenuRowFlash?
    ) -> MenuRowAppearance {
        let isHighlighted: Bool
        if let flash, flash.row == row {
            isHighlighted = flash.isOn
        } else if isTornOff {
            isHighlighted = isHoverable
                && (childSubmenuRow == row
                    || (hoveredRow == row && isDragging)
                    || (hoveredRow == row && childSubmenuRow != nil && isSubmenuRow))
        } else {
            isHighlighted = isHoverable && (childSubmenuRow == row || hoveredRow == row)
        }

        let inChild = (childSubmenuRow == row) && childHasMouse
        return MenuRowAppearance(
            isHighlighted: isHighlighted,
            isEmphasized: !inChild
        )
    }
}
