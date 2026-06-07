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

    func testPressMenuItemPlanPressesOnlyEvenWhenMinimized() {
        XCTAssertEqual(
            MenuActionDispatcher.actionPlan(for: .pressMenuItem, isMinimized: true),
            [.performAction(kAXPressAction as String)]
        )
    }

    func testRaiseAXWindowPlanRaisesOnlyWhenNotMinimized() {
        XCTAssertEqual(
            MenuActionDispatcher.actionPlan(for: .raiseAXWindow, isMinimized: false),
            [.performAction(kAXRaiseAction as String)]
        )
    }

    func testRaiseAXWindowPlanUnminimizesBeforeRaiseWhenMinimized() {
        XCTAssertEqual(
            MenuActionDispatcher.actionPlan(for: .raiseAXWindow, isMinimized: true),
            [.setMinimized(false), .performAction(kAXRaiseAction as String)]
        )
    }
}
