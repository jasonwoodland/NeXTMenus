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
        synthesizedWindowItems: [MenuItem]
    ) -> [MenuItem] {
        guard usesNonPressingWindowPresentation(menuTitle: menuTitle) else { return existingItems }

        let annotatedExistingItems = annotateNativeOpenWindowRows(
            existingItems,
            with: synthesizedWindowItems
        )
        let existingTitles = Set(
            annotatedExistingItems
                .filter { !$0.isSeparator }
                .map(\.title)
                .filter { !$0.isEmpty }
        )
        let missingWindowItems = synthesizedWindowItems.filter { item in
            !item.isSeparator
                && !item.title.isEmpty
                && !existingTitles.contains(item.title)
        }

        guard !missingWindowItems.isEmpty else { return annotatedExistingItems }
        guard !annotatedExistingItems.isEmpty else { return missingWindowItems }

        var result = annotatedExistingItems
        if result.last?.isSeparator != true {
            result.append(separator())
        }
        result.append(contentsOf: missingWindowItems)
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
