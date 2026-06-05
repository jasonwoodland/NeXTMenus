# Phase 3G Submenu Click Intent Plan

## Status

Planning draft. Phase 3G is the next narrow behavior-preserving refactor after Phase 3F. It should not change user-visible interaction semantics.

Phase 3F was merged and pushed as `af77759 refactor: extract hover open interaction gates`, and manual smoke passed before this plan was started.

## Context

Completed groundwork on `main`:

- `4b11d3d refactor: extract main menu row mapping`
- `55891fa refactor: extract menu highlight policy`
- `765b814 fix: stabilize submenu row clicks`
- `cf10af4 refactor: extract submenu open interaction policy`
- `371f0b9 fix: defer torn-off presentation during drag`
- `b7bc17e refactor: extract mouse-up interaction policy`
- `548abc4 refactor: extract mouse-down interaction policy`
- `53f6c7d refactor: extract reset interaction policy`
- `024e595 refactor: extract drag hover interaction policy`
- `af77759 refactor: extract hover open interaction gates`

Current pure interaction policy lives in:

- `Sources/NeXTMenusKit/MenuInteractionState.swift`

Phase 3G targets one remaining submenu interaction helper:

- `Sources/NeXTMenus/SubmenuWindowController.swift`
  - `handleMouseClickedRow(_:)`

This helper is called from the submenu mouse-down path only when `SubmenuMouseDownDecision.action == .handleSubmenuPress(...)`. Mouse-up action behavior is already handled separately by `SubmenuMouseUpIntent` and should not be changed in this phase.

## Goals

1. Preserve current submenu mouse-down click behavior exactly.
2. Extract only the pure clicked-row action decision into `NeXTMenusKit`.
3. Keep row lookup, selectability checks, submenu extraction, presentation, action execution, highlighting, flashing, dismissal, AppKit, and AX side effects in `SubmenuWindowController`.
4. Add focused pure tests for the clicked-row decision, including empty extracted submenu fallback behavior.
5. Keep Phase 3G small enough to review safely before any broader controller decomposition or reducer work.

## Non-goals

- No intentional UX changes.
- No full mouse-event reducer.
- No extraction of all mouse-down behavior.
- No changes to `SubmenuMouseDownDecision` or `SubmenuMouseUpIntent` semantics.
- No changes to main-menu click behavior.
- No changes to `presentSubmenu(for:at:)`, `performAction(_:at:)`, `executeActionAtRow(_:)`, highlighting, flashing, dismissal, torn-off action behavior, or menu refresh behavior.
- No movement of `MenuExtractor`, `NeXTMenusSettings`, AppKit, AX, windows, timers, callbacks, or row/item lookup into `NeXTMenusKit`.
- No attempt to remove the current double-extraction shape where `handleMouseClickedRow(_:)` checks `MenuExtractor.submenuItems(for:)` and `presentSubmenu(for:at:)` re-extracts.

## Current behavior to preserve

### Call path from `handleMouseDown(_:)`

Current ordering/effects in `SubmenuWindowController.handleMouseDown(_:)`:

1. Return if `suppressRowTrackingUntilMouseUp` is true.
2. Return if `clearHoverForScrollCaretIfNeeded()` handles a scroll-caret row.
3. Clear `pressedOpenSubmenuRow` and `pressedDetachedSubmenuRow`.
4. Defer `raiseSubmenuChain()` on the main queue.
5. Compute `isInBounds`, `isSelectable`, and `menuItem` from `visibleMenuItems` and table delegate state.
6. Compute `hasRestorableDetachedSubmenu(...)` lazily only for selectable submenu-capable rows.
7. Ask `MenuInteractionPolicy.submenuMouseDownDecision(...)` what press state/action to apply.
8. Store returned press state.
9. For `.handleSubmenuPress(row:updateTornOffPressHighlight:)`:
   - optionally set torn-off press highlight state;
   - call `handleMouseClickedRow(row)`.

Phase 3G should not change this outer mouse-down decision flow.

### `handleMouseClickedRow(_:)`

Current behavior:

1. Return if the table delegate says the row is not selectable.
2. Read `visibleMenuItems[row]`.
3. Return if `childSubmenuRow == row`; already-open submenu row presses are handled by mouse-up behavior, where attached menus no-op and torn-off menus close on release.
4. If `menuItem.hasSubmenu`, call `MenuExtractor.submenuItems(for: menuItem)`; otherwise use an empty list.
5. If extracted submenu items are non-empty, call `presentSubmenu(for: menuItem, at: row)`.
6. Otherwise, if `menuItem.element` exists, call `performAction(element, at: row)`.
7. Otherwise return.

Important behavior/asymmetries:

- This path is a mouse-down submenu press helper, not the normal leaf mouse-up action path.
- Already-open submenu row press does nothing; mouse-up remains responsible for attached/torn-off differences.
- A submenu-capable row with no extracted submenu items falls through to leaf action if it has an AX element.
- `presentSubmenu(for:at:)` currently re-extracts submenu items and returns if empty. Phase 3G should not change that.
- `performAction(_:at:)` owns flash/action/dismiss/refresh behavior and differs for torn-off versus attached submenus. Phase 3G should not change that.
- `MenuExtractor.submenuItems(for:)` should remain controller-owned and should only be called on the same branch as today: after the row is selectable, not already open, and the item reports `hasSubmenu`.

## Options considered

### Option A: Refactor `presentSubmenu(for:at:)` to accept extracted submenu items

Pros:

- Could avoid double extraction.

Cons:

- Behavior and performance shape change beyond the pure decision extraction.
- Expands the review surface into presentation/window code.

Conclusion: reject for Phase 3G.

### Option B: Extract all mouse-down click handling

Pros:

- Could reduce more controller code.

Cons:

- Too broad for this phase.
- Would risk moving press/highlight/raise-chain/torn-off side effects into the kit.

Conclusion: reject for Phase 3G.

### Option C: Extract only pure clicked-row action intent

Pros:

- Small and testable.
- Keeps side effects in the controller.
- Documents empty-submenu fallback behavior explicitly.
- Fits the existing narrow-slice refactor pattern.

Cons:

- Controller still performs extraction and action/presentation side effects.
- The policy depends on controller-provided facts, including whether extraction produced children.

Recommendation: **Option C**.

## Proposed API

Extend `Sources/NeXTMenusKit/MenuInteractionState.swift` with a submenu clicked-row intent and policy helper.

Possible API shape:

```swift
public enum SubmenuClickedRowActionIntent: Equatable {
    case ignore
    case presentSubmenu(row: Int)
    case performLeafAction(row: Int)
}

public static func submenuClickedRowActionIntent(
    row: Int,
    isInBounds: Bool,
    isSelectable: Bool,
    childSubmenuRow: Int?,
    hasSubmenu: Bool,
    hasExtractedSubmenuItems: Bool,
    hasElement: Bool
) -> SubmenuClickedRowActionIntent
```

Expected decision order:

1. If `row < 0`, `isInBounds == false`, or `isSelectable == false`, return `.ignore`.
2. If `childSubmenuRow == row`, return `.ignore`.
3. If `hasSubmenu == true && hasExtractedSubmenuItems == true`, return `.presentSubmenu(row: row)`.
4. If `hasElement == true`, return `.performLeafAction(row: row)`.
5. Otherwise return `.ignore`.

The helper must be pure. It must not read menu items, extract submenu items, present windows, perform AX actions, update highlights, flash rows, dismiss chains, or mutate controller state.

Controller application shape:

- `handleMouseClickedRow(_:)` computes `isInBounds` before any delegate or item lookup.
- It computes `isSelectable = isInBounds && (tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false)` and must not call the table delegate for out-of-bounds rows, because the delegate path indexes `visibleMenuItems[row]`.
- This in-bounds guard is defensive for the private helper, not a change to the valid mouse-down flow, which already bounds-gates before calling `handleMouseClickedRow(_:)`.
- `handleMouseClickedRow(_:)` keeps its current fresh selectability cadence: it re-checks selectability at click-handling time and must not reuse the earlier `handleMouseDown(_:)` fact.
- It computes `submenuItems` only after fresh selectable, in-bounds, not-already-open, and `menuItem.hasSubmenu`, preserving lazy `MenuExtractor` usage and avoiding broader AX extraction side effects.
- It switches on the pure intent:
  - `.ignore`: return;
  - `.presentSubmenu(row)`: call `presentSubmenu(for: menuItem, at: row)`;
  - `.performLeafAction(row)`: if `menuItem.element` exists, call `performAction(element, at: row)`.
- `presentSubmenu(for:at:)` and `performAction(_:at:)` remain unchanged.
- If the first extraction selects `.presentSubmenu`, the controller keeps the current `presentSubmenu(for:at:)` re-extraction behavior; if that second extraction is empty, `presentSubmenu` returns and no new fallback action is added.
- This helper remains reachable only from the existing `.handleSubmenuPress` mouse-down branch for submenu-capable rows; normal leaf rows must continue performing through mouse-up behavior.

## Files

Modify:

- `Sources/NeXTMenusKit/MenuInteractionState.swift`
- `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift`
- `Sources/NeXTMenus/SubmenuWindowController.swift`

No `MenuWindowController.swift` change is expected for Phase 3G.

No `NeXTMenus.xcodeproj/project.pbxproj` update is expected because no new source file should be needed.

## Test plan

Add focused tests in `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift` before controller rewiring.

Clicked-row action intent tests should assert:

- Off-row/out-of-bounds rows return `.ignore`; implementation review must verify the controller does not call the table delegate before proving the row is in bounds.
- Nonselectable rows return `.ignore`.
- Already-open child submenu rows return `.ignore`, even if other facts indicate a submenu or element.
- Submenu-capable rows with non-empty extracted submenu items return `.presentSubmenu(row:)`.
- Valid sibling submenu rows return `.presentSubmenu(row:)` without any close/pre-collapse decision.
- Submenu-capable rows with empty extracted submenu items and an element return `.performLeafAction(row:)`.
- Submenu-capable rows with empty extracted submenu items and no element return `.ignore`.
- Leaf rows with an element return `.performLeafAction(row:)`.
- Leaf rows without an element return `.ignore`.

Existing open-submenu, hover-gate, async-drag, mouse-up, mouse-down, reset-plan, attached-copy, and highlight policy tests should remain green.

## Implementation steps

1. Confirm `main` is clean and synced with `origin/main`.
2. Confirm `.worktrees/` is ignored:
   - `git check-ignore .worktrees/`
3. Commit this plan doc on `main` after review and user approval, if the main worktree contains only this doc change.
4. Create dedicated implementation worktree after approval:
   - Branch: `refactor/submenu-click-action-intent`
   - Worktree: `.worktrees/refactor/submenu-click-action-intent/`
5. In the worktree, run baseline checks:
   - `swift test`
6. Add failing clicked-row action intent tests in `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift`.
7. Implement `SubmenuClickedRowActionIntent` and `submenuClickedRowActionIntent(...)` in `Sources/NeXTMenusKit/MenuInteractionState.swift`.
8. Run focused tests and confirm they pass:
   - `swift test --filter MenuInteractionStateTests`
9. Refactor `SubmenuWindowController.handleMouseClickedRow(_:)` to use the pure intent while preserving:
   - selectability and bounds handling;
   - already-open child row no-op;
   - `MenuExtractor.submenuItems(for:)` laziness after fresh selectable/in-bounds/not-already-open/has-submenu facts;
   - empty first-extraction fallback to element action;
   - `presentSubmenu(for:at:)` re-extraction behavior, including its current empty-second-extraction no-op with no new fallback action;
   - `performAction(_:at:)` side effects;
   - the call-site boundary where this helper is reached from `.handleSubmenuPress` for submenu-capable mouse-down rows, so normal leaf actions remain on the mouse-up path.
10. Run verification:
    - `git diff --check`
    - `make check-sources`
    - `swift test`
    - `swift build`
    - `make verify`
11. Request implementation review before committing the refactor.
12. Commit only Phase 3G files if review passes.
13. Merge to `main` only after automated verification and targeted manual smoke checks or explicit user instruction to proceed.

## Manual verification matrix

Because Phase 3G touches submenu mouse-down click behavior, manually verify:

- Attached submenu: clicking a submenu row still opens/presents its child immediately.
- Attached submenu: clicking an already-open child row still does not flicker close/reopen on mouse down.
- Attached submenu: leaf row click still performs on mouse-up path as before.
- Torn-off submenu: clicking a submenu row still opens/presents its child and maintains torn-off highlighting behavior.
- Torn-off submenu: clicking an already-open child row still closes on mouse-up, not on mouse-down.
- Torn-off submenu: clicking a leaf row still performs action/refreshes as before.
- Existing Phase 3F hover behavior remains unchanged.

## Risks and mitigations

- **Bounds/selectability drift:** compute `isInBounds` before calling the table delegate, and keep `handleMouseClickedRow(_:)`'s fresh selectability re-check instead of reusing stale mouse-down facts.
- **Extraction timing drift:** keep `MenuExtractor.submenuItems(for:)` in the controller and only compute it on the current fresh selectable, in-bounds, not-already-open, has-submenu branch.
- **Already-open row regression:** preserve mouse-down no-op for `childSubmenuRow == row`; mouse-up remains responsible for attached/torn-off differences.
- **Fallback behavior regression:** preserve empty first-extraction fallback to `performAction` when the item has an element, but do not add any fallback after `presentSubmenu(for:at:)` re-extracts and returns empty.
- **Mouse-down leaf regression:** keep this helper reachable only from the existing `.handleSubmenuPress` mouse-down branch; normal leaf rows must still perform through mouse-up behavior.
- **Side-effect movement:** keep presentation, action execution, flash, dismiss, refresh, AppKit, AX, and window behavior in `SubmenuWindowController`.
- **Double-extraction temptation:** do not change `presentSubmenu(for:at:)` to accept pre-extracted items in this phase.
- **False confidence from pure tests:** policy tests cover decisions; implementation review must still check controller ordering and extraction/action side-effect boundaries.

## Approval gate

Implementation should not start until:

1. This plan is reviewed.
2. Material concerns are addressed.
3. The user approves committing this plan, creating `refactor/submenu-click-action-intent`, and implementing the plan.
