import AppKit
import XCTest
@testable import NeXTMenus
@testable import NeXTMenusKit

final class StaticMenuMetadataLoaderTests: XCTestCase {
    func testMetadataItemsTraverseMenuTitlesIdentifiersAndSubmenus() {
        let mainMenu = NSMenu(title: "Main")
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        windowItem.identifier = NSUserInterfaceItemIdentifier("_NS:458")

        let windowMenu = NSMenu(title: "Window")
        let infoItem = NSMenuItem(title: "Info", action: nil, keyEquivalent: "")
        infoItem.identifier = NSUserInterfaceItemIdentifier("_NS:54")
        windowMenu.addItem(infoItem)
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        let metadata = StaticMenuMetadataLoader.metadataItems(from: mainMenu)

        XCTAssertEqual(metadata.count, 1)
        XCTAssertEqual(metadata[0].identifier, "_NS:458")
        XCTAssertEqual(metadata[0].title, "Window")
        XCTAssertEqual(metadata[0].submenuItems.count, 1)
        XCTAssertEqual(metadata[0].submenuItems[0].identifier, "_NS:54")
        XCTAssertEqual(metadata[0].submenuItems[0].title, "Info")
    }
}
