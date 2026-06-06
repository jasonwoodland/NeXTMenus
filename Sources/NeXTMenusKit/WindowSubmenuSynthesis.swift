public enum WindowSubmenuSynthesis {
    public static func usesNonPressingWindowPresentation(menuTitle: String) -> Bool {
        menuTitle == "Window"
    }

    public static func augmentedItems(
        menuTitle: String,
        existingItems: [MenuItem],
        synthesizedWindowItems: [MenuItem]
    ) -> [MenuItem] {
        guard usesNonPressingWindowPresentation(menuTitle: menuTitle) else { return existingItems }

        let existingTitles = Set(
            existingItems
                .filter { !$0.isSeparator }
                .map(\.title)
                .filter { !$0.isEmpty }
        )
        let missingWindowItems = synthesizedWindowItems.filter { item in
            !item.isSeparator
                && !item.title.isEmpty
                && !existingTitles.contains(item.title)
        }

        guard !missingWindowItems.isEmpty else { return existingItems }
        guard !existingItems.isEmpty else { return missingWindowItems }

        var result = existingItems
        if result.last?.isSeparator != true {
            result.append(separator())
        }
        result.append(contentsOf: missingWindowItems)
        return result
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
