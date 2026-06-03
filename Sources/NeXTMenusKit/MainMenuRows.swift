import Foundation

public enum MainMenuTrailingAction: Equatable {
    case hide
    case quit
    case logOut

    public var title: String {
        switch self {
        case .hide: return "Hide"
        case .quit: return "Quit"
        case .logOut: return "Log Out"
        }
    }

    public var shortcutGlyph: String {
        switch self {
        case .hide: return "⌘H"
        case .quit: return "⌘Q"
        case .logOut: return "⇧⌘Q"
        }
    }
}

public enum MainMenuRowKind: Equatable {
    case appInfo
    case menuItem(index: Int)
    case promotedAppMenuItem(index: Int)
    case trailingAction(MainMenuTrailingAction)
}

public struct MainMenuRows {
    public let appMenuItem: MenuItem?
    public let visibleMenuItems: [MenuItem]
    public let promotedAppMenuItems: [MenuItem]
    public let trailingActions: [MainMenuTrailingAction]

    public init(
        appMenuItem: MenuItem?,
        visibleMenuItems: [MenuItem],
        promotedAppMenuItems: [MenuItem],
        trailingActions: [MainMenuTrailingAction]
    ) {
        self.appMenuItem = appMenuItem
        self.visibleMenuItems = visibleMenuItems
        self.promotedAppMenuItems = promotedAppMenuItems
        self.trailingActions = trailingActions
    }

    public var count: Int {
        1 + visibleMenuItems.count + promotedAppMenuItems.count + trailingActions.count
    }

    public func kind(at row: Int) -> MainMenuRowKind? {
        guard row >= 0, row < count else { return nil }
        if row == 0 { return .appInfo }

        let visibleStart = 1
        let promotedStart = visibleStart + visibleMenuItems.count
        let trailingStart = promotedStart + promotedAppMenuItems.count

        if row < promotedStart {
            return .menuItem(index: row - visibleStart)
        }
        if row < trailingStart {
            return .promotedAppMenuItem(index: row - promotedStart)
        }
        return .trailingAction(trailingActions[row - trailingStart])
    }

    public func menuItem(at row: Int) -> MenuItem? {
        switch kind(at: row) {
        case .appInfo:
            return appMenuItem
        case .menuItem(let index):
            return visibleMenuItems[index]
        case .promotedAppMenuItem(let index):
            return promotedAppMenuItems[index]
        case .trailingAction, nil:
            return nil
        }
    }

    public func trailingAction(at row: Int) -> MainMenuTrailingAction? {
        guard case .trailingAction(let action) = kind(at: row) else { return nil }
        return action
    }

    public func isSelectable(row: Int) -> Bool {
        switch kind(at: row) {
        case .appInfo:
            return appMenuItem?.isEnabled ?? true
        case .menuItem(let index):
            return isSelectable(visibleMenuItems[index])
        case .promotedAppMenuItem(let index):
            return isSelectable(promotedAppMenuItems[index])
        case .trailingAction:
            return true
        case nil:
            return false
        }
    }

    public static func trailingActions(
        showHide: Bool,
        showQuit: Bool,
        isFinderTarget: Bool
    ) -> [MainMenuTrailingAction] {
        var actions: [MainMenuTrailingAction] = []
        if showHide { actions.append(.hide) }
        if showQuit { actions.append(isFinderTarget ? .logOut : .quit) }
        return actions
    }

    public static func promotedServicesItems(
        from appMenuItems: [MenuItem],
        showServices: Bool
    ) -> [MenuItem] {
        guard showServices else { return [] }
        return appMenuItems.filter { !$0.isSeparator && $0.title == "Services" }
    }

    private func isSelectable(_ item: MenuItem) -> Bool {
        item.isEnabled && !item.isSeparator
    }
}
