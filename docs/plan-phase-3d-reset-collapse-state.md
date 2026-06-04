# Phase 3D Reset/Collapse State Plan

## Status

Planning draft. Phase 3D is the next narrow behavior-preserving refactor after Phase 3C. It should not change user-visible interaction semantics.

Manual smoke for Phase 3C passed before this plan was started.

## Context

Completed groundwork on `main`:

- `4b11d3d refactor: extract main menu row mapping`
- `55891fa refactor: extract menu highlight policy`
- `765b814 fix: stabilize submenu row clicks`
- `cf10af4 refactor: extract submenu open interaction policy`
- `371f0b9 fix: defer torn-off presentation during drag`
- `b7bc17e refactor: extract mouse-up interaction policy`
- `548abc4 refactor: extract mouse-down interaction policy`

Current pure interaction policy lives in:

- `Sources/NeXTMenusKit/MenuInteractionState.swift`

Current controller interaction state is spread across:

- `Sources/NeXTMenus/MenuWindowController.swift`
- `Sources/NeXTMenus/SubmenuWindowController.swift`

Phase 3D should continue the narrow-slice pattern by extracting only pure reset/clear-mask decisions. Controllers should still perform all actual state mutation, window hiding, callbacks, timers, highlight updates, AppKit/AX work, and menu extraction.

## Goals

1. Preserve behavior exactly while reducing duplicated reset/clear-state lists in controllers.
2. Add small pure reset/clear-mask plans to `NeXTMenusKit` for known cleanup reasons.
3. Keep reset plans declarative: they describe which state slots to clear and whether pending async submenu opens should be invalidated.
4. Keep all side effects and actual mutation in controllers.
5. Add focused tests for the reset plans, including current controller asymmetries.
6. Keep Phase 3D small enough to review safely before any drag-open or broader reducer work.

## Non-goals

- No intentional UX changes.
- No full interaction reducer.
- No movement of controller-owned state mutation into `NeXTMenusKit`.
- No movement of window hide/order/close/animation into `NeXTMenusKit`.
- No movement of `onWillHide`, `onTornOff`, `dismissChain`, detached submenu retention/pruning/identity, timers, monitors, `updateAllRowHighlights`, table reload/resize, scroll-caret updates, AX actions, `MenuExtractor`, or AppKit state into the kit.
- No changes to row mapping, highlight rendering, scrolling, AX action execution, window ordering, active-app visibility, torn-off levels, submenu extraction, mouse-down/up policies, hover-open policies, or async drag-open behavior.
- No attempt to normalize existing reset asymmetries in this phase.
- No new source file unless implementation evidence shows `MenuInteractionState.swift` is becoming too broad.

## Current behavior to preserve

### Main menu reset and collapse state

Relevant state in `MenuWindowController`:

- `childSubmenuController`
- `childSubmenuRow`
- `hoveredRow`
- `isDragging`
- `pressedRow`
- `pressedRowWasOpen`
- `pressedDetachedSubmenuRow`
- `childHasMouse`
- `isMenuActive`
- `flashState`
- `asyncSubmenuOpenGeneration`

Current behavior by site:

#### `resetInteractionStateForVisibleItemsChange()`

Current ordering/effects:

1. Increment `asyncSubmenuOpenGeneration`.
2. Hide child submenu without animation.
3. Clear child controller and child row.
4. Clear hover.
5. Set `isDragging = false`.
6. Clear all press state.
7. Set `childHasMouse = false`.
8. Set `isMenuActive = false`.
9. Clear `flashState`.

#### `hideWindow()`

Current ordering/effects:

1. Hide child submenu.
2. Clear child controller and child row.
3. Clear hover.
4. Order out the main window.
5. Disable interaction monitoring.

Important asymmetry: `hideWindow()` does **not** clear `isDragging`, press state, `childHasMouse`, `isMenuActive`, `flashState`, or invalidate `asyncSubmenuOpenGeneration`. Phase 3D must not change that unless separately approved.

#### `collapseSubmenus(endsTracking:)`

Current ordering/effects:

1. Increment `asyncSubmenuOpenGeneration`.
2. Hide child submenu.
3. Clear child controller and child row.
4. Clear hover.
5. Set `isDragging = false`.
6. Clear all press state.
7. Set `childHasMouse = false`.
8. If `endsTracking == true`, set `isMenuActive = false`; otherwise preserve tracking.
9. Update all row highlights.

#### child `onTornOff`

Current ordering/effects after detached-reference bookkeeping:

1. Prune detached submenu references.
2. Clear child controller and child row.
3. Clear hover.
4. Set `isDragging = false`.
5. Clear all press state.
6. Set `childHasMouse = false`.
7. Set `isMenuActive = false`.
8. Increment `asyncSubmenuOpenGeneration`.
9. Update all row highlights.

Important asymmetry: unlike `resetInteractionStateForVisibleItemsChange()`, child `onTornOff` does not clear `flashState`.

### Submenu reset and close state

Relevant state in `SubmenuWindowController`:

- `childSubmenuController`
- `childSubmenuRow`
- `hoveredRow`
- `isDragging`
- `pressedOpenSubmenuRow`
- `pressedDetachedSubmenuRow`
- `childHasMouse`
- `flashState`
- torn-off/window flags such as `isTornOff`, `userClosed`, `pendingTornOffPresentation`

Current behavior by site:

#### `closeSubmenu()`

Current ordering/effects:

1. Clear `pressedOpenSubmenuRow`.
2. Clear `pressedDetachedSubmenuRow`.
3. Hide child submenu without animation.
4. Clear child controller and child row.

Important asymmetry: `closeSubmenu()` does **not** clear hover, drag, `childHasMouse`, or `flashState`.

#### `resetInteractionStateForVisibleItemsChange()`

Current ordering/effects:

1. Call `closeSubmenu()`.
2. Clear hover.
3. Set `isDragging = false`.
4. Set `childHasMouse = false`.
5. Clear `flashState`.
6. Clear press state again.

#### `hideTransientAttachedChildChain()`

Current ordering/effects when the child exists and is not detached:

1. Hide child submenu without animation.
2. Clear child controller and child row.
3. Clear hover.
4. Set `isDragging = false`.
5. Clear `pressedOpenSubmenuRow`.
6. Clear `pressedDetachedSubmenuRow`.
7. Set `childHasMouse = false`.
8. Update all row highlights.

Important asymmetry: this does not clear `flashState`.

#### `windowWillClose(_:)`

Current ordering/effects:

1. Set `userClosed = true`.
2. Close child submenu window.
3. Clear child controller and child row.

Important asymmetry: this does not clear hover, drag, press state, `childHasMouse`, or `flashState`.

#### child `onTornOff`

Current ordering/effects after detached-reference bookkeeping:

1. Prune detached submenu references.
2. Clear child controller and child row.
3. Clear hover.
4. Set `isDragging = false`.
5. Clear `pressedDetachedSubmenuRow`.
6. Set `childHasMouse = false`.
7. Update all row highlights.

Important asymmetry: this does **not** clear `pressedOpenSubmenuRow` and does not clear `flashState`.

#### `hideWindow(animated:)`

Current ordering/effects for non-torn-off submenu windows:

1. Return immediately if torn off.
2. Call `onWillHide?()`.
3. Hide child submenu.
4. Clear child controller and child row.
5. Clear hover.
6. Clear `pressedOpenSubmenuRow`.
7. Clear `pressedDetachedSubmenuRow`.
8. Hide/order out the window.

Important asymmetry: this does not clear `isDragging`, `childHasMouse`, or `flashState`.

## Options considered

### Option A: Full reset reducer

Move reset/collapse state transitions into a reducer that owns state values.

Pros:

- Could centralize more behavior.

Cons:

- Too broad for this phase.
- Would risk moving controller state mutation and side effects into the kit.
- Could accidentally normalize existing asymmetries.

### Option B: Controller-only helper methods

Add local helper methods in controllers to reduce duplicated assignments, without a kit-level pure policy.

Pros:

- Small and direct.

Cons:

- Does not add tested pure behavior to `NeXTMenusKit`.
- Makes later policy extraction less explicit.

### Option C: Pure reset-plan / clear-mask extraction

Add small Equatable plans in `NeXTMenusKit` that describe which slots clear for each reason. Controllers apply those plans locally.

Pros:

- Behavior-preserving and testable.
- Keeps side effects and actual mutation in controllers.
- Documents existing asymmetries explicitly.
- Fits the existing `MenuInteractionPolicy` style.

Cons:

- Controllers still need local application helpers.
- Plans have to be named carefully so they do not imply side effects.

Recommendation: **Option C**.

## Proposed API

Extend `Sources/NeXTMenusKit/MenuInteractionState.swift` with reset reason enums and Equatable clear plans.

Possible API shape:

```swift
public enum MainInteractionResetReason: Equatable {
    case collapse(endsTracking: Bool)
    case visibleItemsChanged
    case childTornOff
}

public struct MainInteractionResetPlan: Equatable {
    public let clearChildSubmenu: Bool
    public let clearHoveredRow: Bool
    public let clearDragging: Bool
    public let clearPressedRow: Bool
    public let clearPressedRowWasOpen: Bool
    public let clearPressedDetachedSubmenuRow: Bool
    public let clearChildHasMouse: Bool
    public let deactivateMenu: Bool
    public let clearFlash: Bool
    public let invalidateAsyncSubmenuOpen: Bool
}

public enum SubmenuInteractionResetReason: Equatable {
    case closeChild
    case visibleItemsChanged
    case hideTransientAttachedChild
    case windowWillClose
    case childTornOff
    case hideWindow
}

public struct SubmenuInteractionResetPlan: Equatable {
    public let clearChildSubmenu: Bool
    public let clearHoveredRow: Bool
    public let clearDragging: Bool
    public let clearPressedOpenSubmenuRow: Bool
    public let clearPressedDetachedSubmenuRow: Bool
    public let clearChildHasMouse: Bool
    public let clearFlash: Bool
}

public static func mainResetPlan(for reason: MainInteractionResetReason) -> MainInteractionResetPlan
public static func submenuResetPlan(for reason: SubmenuInteractionResetReason) -> SubmenuInteractionResetPlan
```

Exact field and case names may change during implementation if tests reveal clearer wording. The important boundary is that the plans describe clear/invalidate intent only; controllers still execute all side effects.

Controller application shape:

- Add private controller-local helpers such as `applyInteractionResetPlan(_:)`.
- For `clearChildSubmenu`, the controller clears controller references after performing the existing child hide/close side effect at the same site as today.
- For `invalidateAsyncSubmenuOpen`, main controller increments `asyncSubmenuOpenGeneration` at the same relative site as today.
- For `clearFlash`, controllers set `flashState = nil` only for reset reasons that currently do so.
- `applyInteractionResetPlan(_)` must only mutate local state slots described by the plan. It must not hide/close children, call callbacks, update highlights, increment async generation, prune detached references, order windows, or perform any AppKit/AX work.
- Highlight updates, callback calls, pruning, detached bookkeeping, window ordering, monitoring, and animation remain explicit at call sites.

## Files

Modify:

- `Sources/NeXTMenusKit/MenuInteractionState.swift`
- `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift`
- `Sources/NeXTMenus/MenuWindowController.swift`
- `Sources/NeXTMenus/SubmenuWindowController.swift`

No `NeXTMenus.xcodeproj/project.pbxproj` update is expected because no new source file should be needed.

## Test plan

Add focused tests in `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift` before controller rewiring.

Main reset-plan tests should assert complete plan equality, including false fields:

- `.collapse(endsTracking: true)` clears child, hover, dragging, all press state, child mouse, deactivates menu, invalidates async, and does not clear flash (`clearFlash == false`).
- `.collapse(endsTracking: false)` matches collapse true except it does not deactivate menu.
- `.visibleItemsChanged` clears child, hover, dragging, all press state, child mouse, menu active, flash, and invalidates async.
- `.childTornOff` clears child, hover, dragging, all press state, child mouse, deactivates menu, invalidates async, and does not clear flash (`clearFlash == false`).

Submenu reset-plan tests should assert complete plan equality, including false fields:

- `.closeChild` clears child and both press states only.
- `.visibleItemsChanged` clears child, hover, dragging, both press states, child mouse, and flash.
- `.hideTransientAttachedChild` clears child, hover, dragging, both press states, and child mouse, but not flash.
- `.windowWillClose` clears child only.
- `.childTornOff` clears child, hover, dragging, pressed detached submenu row, and child mouse, but not pressed open submenu row (`clearPressedOpenSubmenuRow == false`) or flash.
- `.hideWindow` clears child, hover, and both press states, but not dragging, child mouse, or flash (`clearDragging == false`, `clearChildHasMouse == false`, `clearFlash == false`).

Existing open-submenu, mouse-up, mouse-down, attached-copy, and highlight policy tests should remain green.

## Implementation steps

1. Confirm `main` is clean and synced with `origin/main`.
2. Confirm `.worktrees/` is ignored:
   - `git check-ignore .worktrees/`
3. Commit this plan doc on `main` after review and user approval, if the main worktree contains only this doc change.
4. Create dedicated implementation worktree after approval:
   - Branch: `refactor/menu-interaction-reset-state`
   - Worktree: `.worktrees/refactor/menu-interaction-reset-state/`
5. In the worktree, run baseline checks:
   - `swift test`
6. Add failing reset-plan tests in `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift`.
7. Implement reset reason enums, clear-plan structs, and policy functions in `Sources/NeXTMenusKit/MenuInteractionState.swift`.
8. Run focused tests and confirm they pass.
9. Refactor `MenuWindowController` reset sites:
   - add a private `applyInteractionResetPlan(_:)` helper;
   - use `MenuInteractionPolicy.mainResetPlan(for:)` in `resetInteractionStateForVisibleItemsChange()`, `collapseSubmenus(endsTracking:)`, and child `onTornOff`;
   - keep child hide calls, detached pruning/bookkeeping, async generation increment timing, highlight updates, window ordering, and monitoring side effects explicit and in place;
   - do **not** refactor main `hideWindow()` in Phase 3D; it is explicitly out of scope and there should be no main `.hideWindow` reset reason.
10. Refactor `SubmenuWindowController` reset sites:
    - add a private `applyInteractionResetPlan(_:)` helper;
    - use `MenuInteractionPolicy.submenuResetPlan(for:)` in `closeSubmenu()`, `resetInteractionStateForVisibleItemsChange()`, `hideTransientAttachedChildChain()`, `windowWillClose(_:)`, child `onTornOff`, and `hideWindow(animated:)` only if exact ordering/side effects remain unchanged;
    - keep window close/hide, callbacks, detached pruning/bookkeeping, highlight updates, and animation side effects explicit and in place;
    - preserve current asymmetries, especially `childTornOff` not clearing `pressedOpenSubmenuRow` and `hideWindow(animated:)` not clearing dragging/child mouse/flash.
11. Run verification:
    - `git diff --check`
    - `make check-sources`
    - `swift test`
    - `swift build`
    - `make verify`
12. Request implementation review before committing the refactor.
13. Commit only Phase 3D files if review passes.
14. Merge to `main` only after automated verification and targeted manual smoke checks or explicit user instruction to proceed.

## Manual verification matrix

Because Phase 3D touches cleanup state, manually verify:

- Main menu: opening a submenu, hovering siblings, and collapsing still updates highlights correctly.
- Main menu: hovering trailing actions while a submenu is open still collapses the child without ending tracking.
- Main menu: Hide/Quit/Log Out flash still works and clears correctly after action.
- Main menu: modifier/visible-item changes close child submenus and clear stale hover/flash.
- Main menu: tearing off a child still clears attached child state and leaves detached copy tracked.
- Attached submenu: leaf hover closes child exactly as before.
- Attached submenu: clicking already-open child row still no-ops.
- Torn-off submenu: clicking already-open child row still closes child on mouse-up.
- Torn-off submenu: app switch still hides transient attached child chains without clearing detached menus.
- User-closing torn-off submenu still does not resurrect on app switch.
- Recent tear-off drag validation remains fixed: tearing off up/down does not jump.

## Risks and mitigations

- **Asymmetry normalization:** treat current differences between reset sites as behavior to preserve, not bugs to fix.
- **Side-effect movement:** keep child hide/close, callbacks, detached pruning/bookkeeping, async increments, highlight updates, window ordering, monitors, timers, AX, and extraction in controllers.
- **Ordering drift:** preserve existing ordering around async generation invalidation, child hide calls, `onWillHide`, detached pruning, and highlight updates.
- **Over-broad refactor temptation:** do not extract drag/hover/open reducers or reset every call site if exact behavior is unclear.
- **Test false confidence:** pure tests cover masks; implementation review must still verify controller application ordering and side-effect boundaries.

## Approval gate

Implementation should not start until:

1. This plan is reviewed.
2. Material concerns are addressed.
3. The user approves committing this plan, creating `refactor/menu-interaction-reset-state`, and implementing the plan.
