import XCTest
@testable import NeXTMenusKit

final class MenuRefreshPolicyTests: XCTestCase {
    func testEmptyCachedTopLevelMenuRetriesWhenNoRetryIsPending() {
        XCTAssertTrue(
            MenuRefreshPolicy.shouldRetryCachedTopLevelMenu(
                extractedTopLevelMenuItemCount: 0,
                isRetryPending: false
            )
        )
    }

    func testFallbackRowsDoNotCountAsLoadedTopLevelMenuItems() {
        // App-info and trailing fallback rows are synthesized by MainMenuRows;
        // retry eligibility is based only on extracted top-level app menu items.
        XCTAssertTrue(
            MenuRefreshPolicy.shouldRetryCachedTopLevelMenu(
                extractedTopLevelMenuItemCount: 0,
                isRetryPending: false
            )
        )
    }

    func testNonEmptyCachedTopLevelMenuDoesNotRetry() {
        XCTAssertFalse(
            MenuRefreshPolicy.shouldRetryCachedTopLevelMenu(
                extractedTopLevelMenuItemCount: 1,
                isRetryPending: false
            )
        )
    }

    func testPendingRetrySuppressesDuplicateRetry() {
        XCTAssertFalse(
            MenuRefreshPolicy.shouldRetryCachedTopLevelMenu(
                extractedTopLevelMenuItemCount: 0,
                isRetryPending: true
            )
        )
    }

    func testOnlyNonEmptyRetryResultsAreApplied() {
        XCTAssertTrue(
            MenuRefreshPolicy.shouldApplyTopLevelMenuRetryResult(
                extractedTopLevelMenuItemCount: 2
            )
        )
        XCTAssertFalse(
            MenuRefreshPolicy.shouldApplyTopLevelMenuRetryResult(
                extractedTopLevelMenuItemCount: 0
            )
        )
    }
}
