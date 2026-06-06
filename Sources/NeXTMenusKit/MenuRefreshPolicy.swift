public enum MenuRefreshPolicy {
    public static func shouldRetryCachedTopLevelMenu(
        extractedTopLevelMenuItemCount: Int,
        isRetryPending: Bool
    ) -> Bool {
        extractedTopLevelMenuItemCount <= 0 && !isRetryPending
    }

    public static func shouldApplyTopLevelMenuRetryResult(
        extractedTopLevelMenuItemCount: Int
    ) -> Bool {
        extractedTopLevelMenuItemCount > 0
    }
}
