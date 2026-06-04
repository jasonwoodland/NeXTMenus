# Phase 3C Mouse-Down Intent Plan

## Status

Planning draft. Phase 3C is the next narrow behavior-preserving refactor after Phase 3B. It should not change user-visible interaction semantics.

## Context

Completed groundwork on `main`:

- `4b11d3d refactor: extract main menu row mapping`
- `55891fa refactor: extract menu highlight policy`
- `765b814 fix: stabilize submenu row clicks`
- `cf10af4 refactor: extract submenu open interaction policy`
- `371f0b9 fix: defer torn-off presentation during drag`
- `b7bc17e refactor: extract mouse-up interaction policy`

Current pure interaction policy lives in:

- `Sources/NeXTMenusKit/MenuInteractionState.swift`

Current policy coverage includes:

- `MainOpenSubmenuIntent`
- `SubmenuOpenSubmenuIntent`
- `MainMouseUpIntent`
- `SubmenuMouseUpIntent`
- `MenuInteractionPolicy.mainOpenSubmenuIntent(...)`
- `MenuInteractionPolicy.submenuOpenSubmenuIntent(...)`
- `MenuInteractionPolicy.mainMouseUpIntent(...)`
- `MenuInteractionPolicy.submenuMouseUpIntent(...)`
- `MenuInteractionPolicy.shouldHideAttachedCopyOnMouseUp(...)`

Remaining mouse-down press-state branching is concentrated in:

- `Sources/NeXTMenus/MenuWindowController.swift`
- `Sources/NeXTMenus/SubmenuWindowController.swift`

`HoverTableView` remains the AppKit event adapter. It stores the mouse-down row, tracks row-change drag state, and emits `onMouseDown(row)` before controller-specific logic runs. Phase 3C should not move event tracking into `NeXTMenusKit`.

## Goals

1. Preserve behavior exactly while reducing branching in controller mouse-down handlers.
2. Extract only pure mouse-down press-state decisions into `NeXTMenusKit`.
3. Keep submenu opening, AX, AppKit, window, timer, highlight, and callback side effects in app controllers.
4. Add focused `NeXTMenusKit` tests for main-menu and submenu mouse-down decisions.
5. Keep Phase 3C small enough to review safely before any broader drag or reducer work.

## Non-goals

- No intentional UX changes.
- No full mouse event reducer.
- No movement of `HoverTableView` event tracking into the kit.
- No movement of `showSubmenu`, `presentSubmenu`, `handleMouseClickedRow`, `performAction`, `MenuExtractor`, or detached identity/AX matching into the kit.
- No changes to row mapping, highlight rendering, scrolling, AX action execution, window ordering, active-app visibility, torn-off levels, or submenu extraction.
- No extraction of drag behavior or async drag-open behavior.
- No reset/collapse state helper cleanup in this phase.
- No movement of `MenuExtractor` or `NeXTMenusSettings` into `NeXTMenusKit`.
- No new source file unless implementation evidence shows `MenuInteractionState.swift` is becoming too broad.

## Current behavior to preserve

### Main menu mouse-down

Current behavior lives in `MenuWindowController.handleMouseDown(_:)`.

Ordering and state:

1. A deferred async `raiseSubmenuChain()` is installed immediately so a click that raises the main menu reasserts the child chain above it.
2. Press state resets before validation:
   - `pressedRow = row >= 0 ? row : nil`
   - `pressedRowWasOpen = false`
   - `pressedDetachedSubmenuRow = nil`
3. Row `< 0` returns after the state reset and deferred chain raise.
4. Non-selectable rows return after the state reset and deferred chain raise. `pressedRow` remains set for non-negative rows even when they are not selectable.
5. Trailing actions (`Hide`, `Quit`, `Log Out`) act on mouse-up; mouse-down only updates highlights for press feedback and returns.
6. If the pressed row is the currently open child row:
   - `pressedRowWasOpen = true`
   - highlights update
   - no submenu is reopened and detached tracking is not checked.
7. If the row has no main menu item or is a separator, return.
8. For a normal menu item row:
   - if there is a restorable detached submenu for the row/current item identity, set `pressedDetachedSubmenuRow = row`;
   - call `showSubmenu(for:at:)`.

Important current semantics:

- Main `pressedRow` is set before selectability checks and should stay that way.
- Main already-open child row handling happens before detached submenu matching, so an already-open child sets `pressedRowWasOpen` and does not set `pressedDetachedSubmenuRow`.
- `showSubmenu(for:at:)` remains controller-owned because it can extract menus, manage windows, or use fallback behavior.
- Press highlight updates remain controller side effects.

### Submenu mouse-down

Current behavior lives in `SubmenuWindowController.handleMouseDown(_:)`.

Ordering and state:

1. Controller-only guards run before press-state clearing:
   - `suppressRowTrackingUntilMouseUp`
   - `clearHoverForScrollCaretIfNeeded()`
2. If either guard returns early, `pressedOpenSubmenuRow` and `pressedDetachedSubmenuRow` are not cleared by this handler.
3. After those guards, press state resets:
   - `pressedOpenSubmenuRow = nil`
   - `pressedDetachedSubmenuRow = nil`
4. A deferred async `raiseSubmenuChain()` is installed after the state reset and before row validation.
5. Invalid, out-of-bounds, and non-selectable rows return after the state reset and deferred chain raise.
6. For a submenu-capable row with a restorable detached submenu, set `pressedDetachedSubmenuRow = row`.
7. If that submenu-capable row is the currently open child row:
   - set `pressedOpenSubmenuRow = row`;
   - if the submenu window is torn off, set `hoveredRow = row`, set `isDragging = true`, and update highlights;
   - return without reopening the child submenu.
8. If the window is torn off and the row was not the already-open child, set `hoveredRow = row`, set `isDragging = true`, and update highlights.
9. If the row has a submenu, call `handleMouseClickedRow(row)`.
10. Leaf rows act on mouse-up, not mouse-down.

Important current semantics:

- Submenu suppression and scroll-caret guards must remain controller-owned before the new policy call.
- Submenu state-clearing happens after those guards and before row validation.
- Submenu detached matching happens before the already-open child branch, so a row can record both `pressedDetachedSubmenuRow` and `pressedOpenSubmenuRow` when both facts are true.
- Torn-off mouse-down highlight behavior uses controller state (`hoveredRow`, `isDragging`) and `updateAllRowHighlights()`; those side effects stay in the controller.
- `handleMouseClickedRow(row)` stays in the controller because it uses `MenuExtractor`, windows, AX elements, and action execution paths.

## Options considered

### Option A: Full mouse event reducer

Move mouse-down, drag, hover, mouse-up, and press state into a unified reducer-like policy.

Pros:

- Could eventually centralize all interaction decisions.

Cons:

- Too broad for this phase.
- Risks behavior drift across AppKit event ordering, torn-off menus, drag-open behavior, and AX/window side effects.
- Conflicts with the established narrow-slice strategy.

### Option B: Mouse-down plus drag intent extraction

Extract both press-state decisions and drag/open behavior.

Pros:

- Would reduce more controller branching in one pass.

Cons:

- Drag behavior includes async extraction, child pointer tracking, hover updates, and open-submenu policies that have distinct timing constraints.
- Higher risk than needed after Phase 3B.

### Option C: Mouse-down press-state-only extraction

Extract only the pure decisions that set mouse-down press markers and choose declarative controller actions.

Pros:

- Smallest useful Phase 3C slice.
- Builds on the existing `MenuInteractionPolicy` intent style.
- Keeps AppKit/AX/window/highlight side effects in controllers.
- Gives focused tests for ordering-sensitive press-state behavior.

Cons:

- Leaves drag behavior and some controller guard structure for later phases.
- Requires controllers to compute row facts safely before calling policy.

Recommendation: **Option C**.

## Proposed API

Extend `Sources/NeXTMenusKit/MenuInteractionState.swift` with mouse-down decision structs and action enums.

Possible API shape:

```swift
public enum MainMouseDownAction: Equatable {
    case none
    case updateHighlights
    case showSubmenu(row: Int)
}

public struct MainMouseDownDecision: Equatable {
    public let pressedRow: Int?
    public let pressedRowWasOpen: Bool
    public let pressedDetachedSubmenuRow: Int?
    public let action: MainMouseDownAction
}

public enum SubmenuMouseDownAction: Equatable {
    case none
    case updateTornOffPressHighlight(row: Int)
    case handleSubmenuPress(row: Int, updateTornOffPressHighlight: Bool)
}

public struct SubmenuMouseDownDecision: Equatable {
    public let pressedOpenSubmenuRow: Int?
    public let pressedDetachedSubmenuRow: Int?
    public let action: SubmenuMouseDownAction
}

public static func mainMouseDownDecision(
    row: Int,
    isSelectable: Bool,
    isTrailingAction: Bool,
    childSubmenuRow: Int?,
    hasMenuItem: Bool,
    isSeparator: Bool,
    hasRestorableDetachedSubmenu: Bool
) -> MainMouseDownDecision

public static func submenuMouseDownDecision(
    row: Int,
    isInBounds: Bool,
    isSelectable: Bool,
    isTornOff: Bool,
    childSubmenuRow: Int?,
    hasSubmenu: Bool,
    hasRestorableDetachedSubmenu: Bool
) -> SubmenuMouseDownDecision
```

Exact case names can be adjusted during implementation if tests reveal clearer wording. The important boundary is that policy returns only press-state values and declarative actions; controllers still execute all side effects.

Controller-side fact computation:

- Main controller computes `isSelectable`, `isTrailingAction`, `mainMenuItem(at:)`, and separator state safely. It must compute `hasRestorableDetachedSubmenu` **lazily/conditionally only after** confirming the row is non-negative, selectable, not a trailing action, not already open, has a menu item, and is not a separator. This preserves current behavior because `hasRestorableDetachedSubmenu(...)` prunes detached references and is not a purely observational helper.
- Submenu controller keeps suppression/scroll-caret guards before policy, then computes `isInBounds`, `isSelectable`, and `visibleMenuItems[row]` facts safely. It must compute `hasRestorableDetachedSubmenu` **lazily/conditionally only for selectable submenu-capable rows**, before already-open handling. This preserves current behavior where detached+already-open submenu rows can record both press states.
- Controllers apply the returned state values, then switch on the returned action.

Controller-owned effects after policy:

- Main `.updateHighlights` calls `updateAllRowHighlights()`.
- Main `.showSubmenu(row:)` fetches the already-computed menu item and calls `showSubmenu(for:at:)`.
- Submenu `.updateTornOffPressHighlight(row:)` sets `hoveredRow`, sets `isDragging`, and calls `updateAllRowHighlights()`.
- Submenu `.handleSubmenuPress(row:updateTornOffPressHighlight:)` optionally applies the torn-off press highlight and then calls `handleMouseClickedRow(row)`.

## Files

Modify:

- `Sources/NeXTMenusKit/MenuInteractionState.swift`
- `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift`
- `Sources/NeXTMenus/MenuWindowController.swift`
- `Sources/NeXTMenus/SubmenuWindowController.swift`

No `NeXTMenus.xcodeproj/project.pbxproj` update is expected because no new source file should be needed.

## Test plan

Add focused tests in `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift` before controller rewiring.

Main mouse-down policy tests:

- Off-row returns `pressedRow == nil`, cleared flags, and `.none`.
- Non-selectable non-negative row preserves `pressedRow == row`, clears other flags, and returns `.none`.
- Trailing action row returns `pressedRow == row`, cleared flags, and `.updateHighlights`.
- Already-open child row returns `pressedRow == row`, `pressedRowWasOpen == true`, no detached row, and `.updateHighlights`.
- Already-open child row wins over `hasRestorableDetachedSubmenu == true`; implementation must also avoid calling the detached helper for this branch.
- `hasRestorableDetachedSubmenu == true` is ignored for nonselectable and trailing rows; implementation must avoid calling the detached helper for those branches.
- Missing menu item returns `.none` after setting `pressedRow`; implementation must avoid calling the detached helper for this branch.
- Separator row returns `.none` after setting `pressedRow`; implementation must avoid calling the detached helper for this branch.
- Normal menu item returns `.showSubmenu(row:)` with no detached row.
- Normal row with restorable detached submenu returns `.showSubmenu(row:)` and `pressedDetachedSubmenuRow == row`.

Submenu mouse-down policy tests:

- Invalid/off-row returns cleared press rows and `.none`.
- High out-of-bounds row returns cleared press rows and `.none`.
- Non-selectable row returns cleared press rows and `.none`.
- Attached leaf row returns cleared press rows and `.none`.
- Torn-off leaf row returns cleared press rows and `.updateTornOffPressHighlight(row:)`.
- Attached submenu row returns `.handleSubmenuPress(row:updateTornOffPressHighlight: false)`.
- Torn-off submenu row returns `.handleSubmenuPress(row:updateTornOffPressHighlight: true)`.
- Restorable detached submenu row records `pressedDetachedSubmenuRow == row` before handling submenu press.
- `hasRestorableDetachedSubmenu == true` is ignored for invalid, nonselectable, and leaf rows; implementation must avoid calling the detached helper for those branches.
- Attached already-open submenu row records `pressedOpenSubmenuRow == row` and returns `.none`.
- Torn-off already-open submenu row records `pressedOpenSubmenuRow == row` and returns `.updateTornOffPressHighlight(row:)`.
- If a submenu row is both restorable detached and already open, submenu policy records both `pressedDetachedSubmenuRow == row` and `pressedOpenSubmenuRow == row`, preserving current ordering.

Existing open-submenu, mouse-up, attached-copy, and highlight policy tests should remain green.

## Implementation steps

1. Confirm `main` is clean and synced with `origin/main`.
2. Confirm `.worktrees/` is ignored:
   - `git check-ignore .worktrees/`
3. Commit this plan doc on `main` after review and user approval, if the main worktree contains only this doc change.
4. Create dedicated implementation worktree after approval:
   - Branch: `refactor/menu-interaction-mouse-down`
   - Worktree: `.worktrees/refactor/menu-interaction-mouse-down/`
5. In the worktree, run baseline checks:
   - `swift test`
6. Add failing policy tests in `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift`.
7. Implement `MainMouseDownAction`, `MainMouseDownDecision`, `SubmenuMouseDownAction`, `SubmenuMouseDownDecision`, and policy functions in `Sources/NeXTMenusKit/MenuInteractionState.swift`.
8. Run focused tests and confirm they pass.
9. Refactor `MenuWindowController.handleMouseDown(_:)`:
   - preserve deferred async `raiseSubmenuChain()` placement;
   - compute row facts safely;
   - compute `hasRestorableDetachedSubmenu(...)` lazily only for the same branch that currently calls it, because it prunes detached references;
   - call `MenuInteractionPolicy.mainMouseDownDecision(...)`;
   - assign returned press-state fields;
   - switch over the returned action and call existing controller side effects.
10. Refactor `SubmenuWindowController.handleMouseDown(_:)`:
    - preserve `suppressRowTrackingUntilMouseUp` and `clearHoverForScrollCaretIfNeeded()` before clearing state or calling policy;
    - preserve deferred async `raiseSubmenuChain()` placement after those guards and after state reset;
    - compute row facts safely before indexing;
    - compute `hasRestorableDetachedSubmenu(...)` lazily only for selectable submenu-capable rows, before already-open handling, because it prunes detached references;
    - call `MenuInteractionPolicy.submenuMouseDownDecision(...)`;
    - assign returned press-state fields;
    - switch over the returned action and call existing controller side effects.
11. Run verification:
    - `git diff --check`
    - `make check-sources`
    - `swift test`
    - `swift build`
    - `make verify`
12. Request implementation review before committing the refactor.
13. Commit only Phase 3C files if review passes.
14. Merge to `main` only after automated verification and targeted manual smoke checks.

## Manual verification matrix

Because Phase 3C touches mouse-down press-state behavior, manually verify:

- Main menu: click a normal row opens its submenu immediately.
- Main menu: click the already-open row still defers toggle-close to mouse-up.
- Main menu: press Hide/Quit/Log Out highlights on press and acts on release.
- Main menu: non-selectable rows do not open submenus.
- Already-torn-off main row click still opens a temporary attached copy on press and hides only that attached copy on mouse-up.
- Attached submenu: click a submenu-capable row opens/presents the child immediately.
- Attached submenu: clicking the already-open child row still no-ops until mouse-up handling.
- Torn-off submenu: pressing a row still highlights it immediately.
- Torn-off submenu: clicking an already-open child row still highlights on press and closes child on mouse-up.
- Already-torn-off nested row click still opens a temporary attached copy on press and hides only that attached copy on mouse-up.
- Scroll-caret and suppressed row-tracking paths still return before clearing submenu press state.
- Recent torn-off validation remains fixed: tear-off dragging up/down does not jump.

## Risks and mitigations

- **Main `pressedRow` ordering drift:** preserve setting `pressedRow` for non-negative rows before selectability decisions.
- **Submenu guard ordering drift:** keep suppression and scroll-caret guards before press-state clearing and policy calls.
- **Detached helper eagerness:** `hasRestorableDetachedSubmenu(...)` prunes stale references, so controllers must compute it lazily only on branches that currently call it.
- **Detached/open-child precedence drift:** preserve main already-open-before-detached ordering and submenu detached-before-already-open ordering.
- **Torn-off press highlight regression:** keep `hoveredRow`, `isDragging`, and highlight updates in the controller and test the pure action that asks for them.
- **Unsafe indexing:** compute `isInBounds` before accessing `visibleMenuItems[row]`; use safe main row/item helpers.
- **Side-effect creep into kit:** do not move `showSubmenu`, `handleMouseClickedRow`, `MenuExtractor`, AX, windows, or highlights into `NeXTMenusKit`.
- **Over-broad refactor temptation:** do not extract drag, hover, reset/collapse, or full reducer behavior in Phase 3C.
- **Manual-only AppKit behavior:** automated tests cover pure press-state decisions; runtime AppKit interaction still needs targeted smoke testing.

## Approval gate

Implementation should not start until:

1. This plan is reviewed.
2. Material concerns are addressed.
3. The user approves committing this plan, creating `refactor/menu-interaction-mouse-down`, and implementing the plan.
