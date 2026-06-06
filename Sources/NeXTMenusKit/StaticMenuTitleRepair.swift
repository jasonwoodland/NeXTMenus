import Foundation

public struct StaticMenuItemMetadata: Equatable {
    public let identifier: String?
    public let title: String
    public let submenuItems: [StaticMenuItemMetadata]

    public init(
        identifier: String?,
        title: String,
        submenuItems: [StaticMenuItemMetadata] = []
    ) {
        self.identifier = identifier
        self.title = title
        self.submenuItems = submenuItems
    }
}

public enum StaticMenuTitleRepair {
    public static func repairedItems(
        _ runtimeItems: [MenuItem],
        using staticItems: [StaticMenuItemMetadata]
    ) -> [MenuItem] {
        let titleByIdentifier = uniqueTitlesByIdentifier(in: staticItems)
        return runtimeItems.map { repair($0, titleByIdentifier: titleByIdentifier) }
    }

    private static func repair(
        _ item: MenuItem,
        titleByIdentifier: [String: String?]
    ) -> MenuItem {
        let repairedSubmenuItems = item.submenuItems.map {
            repair($0, titleByIdentifier: titleByIdentifier)
        }
        let replacementTitle = repairedTitle(for: item, titleByIdentifier: titleByIdentifier)
        let title = replacementTitle ?? item.title
        let isSeparator = replacementTitle == nil ? item.isSeparator : false

        return MenuItem(
            title: title,
            isEnabled: item.isEnabled,
            hasSubmenu: item.hasSubmenu,
            isSeparator: isSeparator,
            element: item.element,
            submenuItems: repairedSubmenuItems,
            keyEquivalent: item.keyEquivalent,
            requiredModifiers: item.requiredModifiers,
            isAlternate: item.isAlternate,
            alternateTitle: item.alternateTitle,
            cmdGlyph: item.cmdGlyph,
            markChar: item.markChar,
            cmdChar: item.cmdChar,
            cmdModifiers: item.cmdModifiers,
            actionKind: item.actionKind,
            axIdentifier: item.axIdentifier
        )
    }

    private static func repairedTitle(
        for item: MenuItem,
        titleByIdentifier: [String: String?]
    ) -> String? {
        guard isRepairableRuntimeTitle(item.title, isSeparator: item.isSeparator),
              let identifier = item.axIdentifier,
              let title = titleByIdentifier[identifier] ?? nil,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return title
    }

    private static func uniqueTitlesByIdentifier(
        in items: [StaticMenuItemMetadata]
    ) -> [String: String?] {
        var titlesByIdentifier = [String: Set<String>]()
        collectTitles(from: items, into: &titlesByIdentifier)

        return titlesByIdentifier.reduce(into: [String: String?]()) { result, entry in
            result[entry.key] = entry.value.count == 1 ? entry.value.first : nil
        }
    }

    private static func collectTitles(
        from items: [StaticMenuItemMetadata],
        into titlesByIdentifier: inout [String: Set<String>]
    ) {
        for item in items {
            if let identifier = item.identifier,
               !identifier.isEmpty,
               !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                titlesByIdentifier[identifier, default: []].insert(item.title)
            }
            collectTitles(from: item.submenuItems, into: &titlesByIdentifier)
        }
    }

    private static func isRepairableRuntimeTitle(_ title: String, isSeparator: Bool) -> Bool {
        if isSeparator { return true }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.allSatisfy { $0 == "-" }
    }
}
