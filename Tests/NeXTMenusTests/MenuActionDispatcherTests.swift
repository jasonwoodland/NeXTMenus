import ApplicationServices
import XCTest
@testable import NeXTMenus
@testable import NeXTMenusKit

final class MenuActionDispatcherTests: XCTestCase {
    func testPressMenuItemDispatchesAXPressAction() {
        XCTAssertEqual(
            MenuActionDispatcher.axActionName(for: .pressMenuItem) as String,
            kAXPressAction as String
        )
    }

    func testRaiseAXWindowDispatchesAXRaiseAction() {
        XCTAssertEqual(
            MenuActionDispatcher.axActionName(for: .raiseAXWindow) as String,
            kAXRaiseAction as String
        )
    }
}
