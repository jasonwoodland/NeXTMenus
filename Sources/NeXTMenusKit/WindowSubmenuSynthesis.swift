import Foundation

public enum WindowSubmenuSynthesis {
    private static let nativeOpenWindowIdentifier = "makeKeyAndOrderFront:"
    private static let minimizedWindowMark = "◆"

    public static func usesNonPressingWindowPresentation(menuTitle: String) -> Bool {
        menuTitle == "Window"
    }

    public static func windowMarkChar(isFocused: Bool, isMinimized: Bool) -> String? {
        if isMinimized { return minimizedWindowMark }
        if isFocused { return "✓" }
        return nil
    }

    public static func augmentedItems(
        menuTitle: String,
        existingItems: [MenuItem],
        synthesizedWindowItems: [MenuItem],
        orderedWindowTitles: [String] = []
    ) -> [MenuItem] {
        guard usesNonPressingWindowPresentation(menuTitle: menuTitle) else { return existingItems }

        let annotatedExistingItems = annotateNativeOpenWindowRows(
            existingItems,
            with: synthesizedWindowItems
        )
        let orderedExistingItems = reorderNativeOpenWindowRows(
            annotatedExistingItems,
            orderedWindowTitles: orderedWindowTitles
        )
        let existingTitles = Set(
            orderedExistingItems
                .filter { !$0.isSeparator }
                .map(\.title)
                .filter { !$0.isEmpty }
        )
        let missingWindowItems = synthesizedWindowItems.filter { item in
            !item.isSeparator
                && !item.title.isEmpty
                && !existingTitles.contains(item.title)
        }

        guard !missingWindowItems.isEmpty else { return orderedExistingItems }
        guard !orderedExistingItems.isEmpty else { return missingWindowItems }

        var result = orderedExistingItems
        if result.last?.isSeparator != true {
            result.append(separator())
        }
        result.append(contentsOf: missingWindowItems)
        return result
    }

    private static func reorderNativeOpenWindowRows(
        _ items: [MenuItem],
        orderedWindowTitles: [String]
    ) -> [MenuItem] {
        guard items.count >= 2,
              let normalizedOrderedTitles = normalizedUniqueTitles(orderedWindowTitles),
              !normalizedOrderedTitles.isEmpty else {
            return items
        }

        let windowRowIndices = items.indices.filter { isNativeOpenWindowRow(items[$0]) }
        guard windowRowIndices.count >= 2,
              let firstWindowRow = windowRowIndices.first,
              let lastWindowRow = windowRowIndices.last else {
            return items
        }

        guard (firstWindowRow...lastWindowRow).allSatisfy({ isNativeOpenWindowRow(items[$0]) }) else {
            return items
        }

        let windowRows = Array(items[firstWindowRow...lastWindowRow])
        guard let windowRowTitles = normalizedUniqueTitles(windowRows.map(\.title)),
              Set(windowRowTitles) == Set(normalizedOrderedTitles) else {
            return items
        }

        let orderByTitle = Dictionary(uniqueKeysWithValues: normalizedOrderedTitles.enumerated().map { index, title in
            (title, index)
        })
        let sortedWindowRows = windowRows.sorted { lhs, rhs in
            let lhsOrder = orderByTitle[normalizedTitle(lhs.title)!]!
            let rhsOrder = orderByTitle[normalizedTitle(rhs.title)!]!
            return lhsOrder < rhsOrder
        }

        var result = items
        result.replaceSubrange(firstWindowRow...lastWindowRow, with: sortedWindowRows)
        return result
    }

    private static func annotateNativeOpenWindowRows(
        _ existingItems: [MenuItem],
        with synthesizedWindowItems: [MenuItem]
    ) -> [MenuItem] {
        let windowMarksByTitle = synthesizedWindowItems.reduce(into: [String: String?]()) { result, item in
            guard !item.isSeparator, !item.title.isEmpty else { return }
            result.updateValue(normalizedWindowMark(item.markChar), forKey: item.title)
        }

        guard !windowMarksByTitle.isEmpty else { return existingItems }

        return existingItems.map { item in
            guard isNativeOpenWindowRow(item),
                  let currentMark = windowMarksByTitle[item.title] else {
                return item
            }

            var annotatedItem = item
            annotatedItem.markChar = currentMark
            return annotatedItem
        }
    }

    private static func isNativeOpenWindowRow(_ item: MenuItem) -> Bool {
        guard !item.isSeparator,
              item.actionKind == .pressMenuItem,
              normalizedIdentifier(item.axIdentifier) == nativeOpenWindowIdentifier else {
            return false
        }
        return true
    }

    private static func normalizedUniqueTitles(_ titles: [String]) -> [String]? {
        var result = [String]()
        var seen = Set<String>()
        for title in titles {
            guard let normalized = normalizedTitle(title), seen.insert(normalized).inserted else {
                return nil
            }
            result.append(normalized)
        }
        return result
    }

    private static func normalizedTitle(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedIdentifier(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedWindowMark(_ markChar: String?) -> String? {
        guard let markChar else { return nil }
        let trimmed = markChar.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func separator() -> MenuItem {
        MenuItem(
            title: "",
            isEnabled: false,
            hasSubmenu: false,
            isSeparator: true,
            element: nil,
            submenuItems: [],
            keyEquivalent: nil,
            requiredModifiers: nil,
            isAlternate: false,
            alternateTitle: nil,
            cmdGlyph: nil,
            markChar: nil,
            cmdChar: nil,
            cmdModifiers: nil
        )
    }
}
