import ApplicationServices
import XCTest
@testable import NeXTMenus

final class ApplicationObserverTests: XCTestCase {
    func testAppElementNotificationNamesIncludeMainWindowAndExcludeFocusedUI() {
        XCTAssertEqual(
            Set(ApplicationObserver.appElementNotificationNames),
            Set([
                kAXFocusedWindowChangedNotification as String,
                kAXWindowCreatedNotification as String,
                kAXMainWindowChangedNotification as String
            ])
        )
        XCTAssertFalse(
            ApplicationObserver.appElementNotificationNames.contains(kAXFocusedUIElementChangedNotification as String)
        )
    }

    func testFocusedWindowMovementNotificationNamesRemainMoveAndResizeOnly() {
        XCTAssertEqual(
            Set(ApplicationObserver.focusedWindowMovementNotificationNames),
            Set([
                kAXMovedNotification as String,
                kAXResizedNotification as String
            ])
        )
    }

    func testObservedWindowNotificationNamesIncludeTabRelatedSignalsAndExcludeFocusedUI() {
        XCTAssertEqual(
            Set(ApplicationObserver.observedWindowNotificationNames),
            Set([
                kAXWindowMiniaturizedNotification as String,
                kAXWindowDeminiaturizedNotification as String,
                kAXTitleChangedNotification as String,
                kAXSelectedChildrenChangedNotification as String
            ])
        )
        XCTAssertFalse(
            ApplicationObserver.observedWindowNotificationNames.contains(kAXFocusedUIElementChangedNotification as String)
        )
    }

    func testFocusedMovementObservationPolicyHandlesFocusedAndMainWindowChangesOnly() {
        XCTAssertTrue(ApplicationObserver.shouldUpdateFocusedWindowMovementObservation(
            for: kAXFocusedWindowChangedNotification as String
        ))
        XCTAssertTrue(ApplicationObserver.shouldUpdateFocusedWindowMovementObservation(
            for: kAXMainWindowChangedNotification as String
        ))
        XCTAssertFalse(ApplicationObserver.shouldUpdateFocusedWindowMovementObservation(
            for: kAXTitleChangedNotification as String
        ))
        XCTAssertFalse(ApplicationObserver.shouldUpdateFocusedWindowMovementObservation(
            for: kAXSelectedChildrenChangedNotification as String
        ))
    }

    func testObservedWindowSetRefreshPolicyHandlesLifecycleAndSelectedChildrenButNotTitleOnly() {
        XCTAssertTrue(ApplicationObserver.shouldRefreshObservedWindowSet(
            for: kAXFocusedWindowChangedNotification as String
        ))
        XCTAssertTrue(ApplicationObserver.shouldRefreshObservedWindowSet(
            for: kAXMainWindowChangedNotification as String
        ))
        XCTAssertTrue(ApplicationObserver.shouldRefreshObservedWindowSet(
            for: kAXWindowCreatedNotification as String
        ))
        XCTAssertTrue(ApplicationObserver.shouldRefreshObservedWindowSet(
            for: kAXWindowMiniaturizedNotification as String
        ))
        XCTAssertTrue(ApplicationObserver.shouldRefreshObservedWindowSet(
            for: kAXWindowDeminiaturizedNotification as String
        ))
        XCTAssertTrue(ApplicationObserver.shouldRefreshObservedWindowSet(
            for: kAXSelectedChildrenChangedNotification as String
        ))
        XCTAssertFalse(ApplicationObserver.shouldRefreshObservedWindowSet(
            for: kAXTitleChangedNotification as String
        ))
        XCTAssertFalse(ApplicationObserver.shouldRefreshObservedWindowSet(
            for: kAXFocusedUIElementChangedNotification as String
        ))
    }
}
