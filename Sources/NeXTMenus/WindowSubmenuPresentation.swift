import Cocoa
#if SWIFT_PACKAGE
import NeXTMenusKit
#endif

enum WindowSubmenuPresentation {
    static func submenuItems(
        for menuItem: MenuItem,
        targetApp: NSRunningApplication?
    ) -> [MenuItem] {
        guard WindowSubmenuSynthesis.usesNonPressingWindowPresentation(menuTitle: menuItem.title) else {
            return MenuExtractor.submenuItems(for: menuItem)
        }

        let nativeItems = MenuExtractor.submenuItemsWithoutOpeningNativeMenu(for: menuItem)
        let repairedNativeItems = StaticMenuTitleRepair.repairedItems(
            nativeItems,
            using: StaticMenuMetadataLoader.metadataItems(for: targetApp)
        )
        let orderedWindowTitles = targetApp.map { MenuExtractor.orderedWindowTabTitles(for: $0) } ?? []
        let windowItems = targetApp.map { MenuExtractor.synthesizedWindowItems(for: $0) } ?? []
        return WindowSubmenuSynthesis.augmentedItems(
            menuTitle: menuItem.title,
            existingItems: repairedNativeItems,
            synthesizedWindowItems: windowItems,
            orderedWindowTitles: orderedWindowTitles
        )
    }
}
