# Phase 3B Press/Release Intent Plan

## Status

Planning draft. This is the next narrow behavior-preserving refactor after Phase 3A and the torn-off menu behavior fix. It should not change user-visible interaction semantics.

## Context

Completed groundwork on `main`:

- `4b11d3d refactor: extract main menu row mapping`
- `55891fa refactor: extract menu highlight policy`
- `765b814 fix: stabilize submenu row clicks`
- `cf10af4 refactor: extract submenu open interaction policy`
- `371f0b9 fix: defer torn-off presentation during drag`

Current pure interaction policy lives in:

- `Sources/NeXTMenusKit/MenuInteractionState.swift`

Current policy coverage includes:

- `MainOpenSubmenuIntent`
- `SubmenuOpenSubmenuIntent`
- `MenuInteractionPolicy.mainOpenSubmenuIntent(...)`
- `MenuInteractionPolicy.submenuOpenSubmenuIntent(...)`
- `MenuInteractionPolicy.shouldHideAttachedCopyOnMouseUp(...)`

Remaining mouse press/release branching is concentrated in:

- `Sources/NeXTMenus/MenuWindowController.swift`
- `Sources/NeXTMenus/SubmenuWindowController.swift`

`HoverTableView` is the AppKit event adapter. It stores `mouseDownRow`, tracks whether the pointer moved to a different row, and emits:

- `onMouseDown(row)`
- `onMouseDraggedOverRow(row)`
- `onMouseUp(row, wasDragged)` where `wasDragged` means the pointer moved to a different row since mouse-down
- `onMouseLongPressReleased(row)` routed by controllers through the normal mouse-up path

## Goals

1. Preserve behavior exactly while reducing branching in controller mouse-up handlers.
2. Extract only pure mouse-up press/release decision logic into `NeXTMenusKit`.
3. Keep all AppKit, AX, window, timer, highlight, and callback side effects in app controllers.
4. Add focused `NeXTMenusKit` tests for main-menu and submenu mouse-up decisions.
5. Keep Phase 3B small enough to review safely before later broader interaction-state work.

## Non-goals

- No intentional UX changes.
- No full mouse event reducer.
- No wholesale movement of `handleMouseDown`, `handleMouseDragged`, or `handleMouseUp` into the kit.
- No movement of `HoverTableView` event tracking into the kit.
- No changes to row mapping, highlight rendering, scrolling, AX action execution, window ordering, active-app visibility, torn-off levels, or submenu extraction.
- No movement of `MenuExtractor` or `NeXTMenusSettings` into `NeXTMenusKit`.
- No new source file unless implementation evidence shows `MenuInteractionState.swift` is becoming too broad.

## Current behavior to preserve

### Main menu mouse-up

Current behavior lives in `MenuWindowController.handleMouseUp(_:wasDragged:)`.

Before branching, the controller snapshots and clears press state:

- `pressedRow`
- `pressedRowWasOpen`
- `pressedDetachedSubmenuRow`
- `isDragging`

Behavior and ordering:

1. Trailing actions (`Hide`, `Quit`, `Log Out`) fire on release when `trailingAction(at: row)` returns an action. The controller calls `performTrailingAction(action, at: row)` and returns.
2. Row `< 0` clears hover. If a child submenu is open, it collapses submenus; otherwise it marks the menu inactive and updates highlights.
3. Non-selectable rows clear hover and collapse submenus.
4. Already-torn-off attached-copy mouse-up uses `MenuInteractionPolicy.shouldHideAttachedCopyOnMouseUp(...)`; if it matches, it collapses only the temporary attached chain and returns.
5. Toggle-close: if release is not dragged, the pressed row was already open at mouse-down, and the release row equals the pressed row, it collapses submenus and returns.
6. Otherwise, click-drag-and-release on a main menu item keeps submenu parents open in tracking mode. The controller schedules `raiseSubmenuChain()` asynchronously.

Important current semantics:

- Trailing actions currently run before row `< 0` and selectability checks. Because `trailingAction(at:)` guards its own bounds, this is safe and should remain behavior-preserving.
- Main menu leaf/fallback execution can happen earlier through `showSubmenu(for:at:)` from mouse-down or drag-open paths; Phase 3B must not move or reinterpret that behavior.
- `collapseSubmenus()` and `performTrailingAction(...)` remain controller side effects.

### Submenu mouse-up

Current behavior lives in `SubmenuWindowController.handleMouseUp(_:wasDragged:)`.

Before most branching, the controller snapshots and clears press state:

- `pressedOpenSubmenuRow`
- `pressedDetachedSubmenuRow`

It then lets scroll-caret release handling exit early, clears `isDragging`, and defers an async `raiseSubmenuChain()`.

Important ordering detail: the snapshot and clearing of `pressedOpenSubmenuRow` and `pressedDetachedSubmenuRow` currently happens before `clearHoverForScrollCaretIfNeeded()`. If the scroll-caret path returns early, `isDragging` is not cleared by `handleMouseUp` and the async `raiseSubmenuChain()` defer is not installed. Phase 3B must preserve that ordering exactly.

Behavior and ordering:

1. Row `< 0` clears hover, closes the current child submenu, updates highlights, and:
   - if torn off, keeps the torn-off menu visible;
   - if attached, calls `dismissChain?()` to cancel the whole tracking chain.
2. High out-of-bounds rows (`row >= visibleMenuItems.count`) return without side effects except the deferred chain raise.
3. Non-selectable rows clear hover, close the child submenu, update highlights, and dismiss the chain only when attached.
4. For submenu-capable rows:
   - already-torn-off attached-copy mouse-up uses `MenuInteractionPolicy.shouldHideAttachedCopyOnMouseUp(...)`; if it matches, it closes only the temporary attached child, clears hover, updates highlights, and returns;
   - if the pressed already-open child row is released on the same child row, attached menus no-op and torn-off menus close the child, clear hover, update highlights, then return;
   - if this was a drag release on the open child row, close the child and update highlights, then return;
   - otherwise return with no leaf action.
5. For leaf rows with no AX element, return.
6. For leaf rows with an AX element:
   - if torn off, clear hover and update highlights;
   - perform the AX action via `performAction(element, at: row)`, which remains controller-owned.

Important current semantics:

- `clearHoverForScrollCaretIfNeeded()` must stay in the controller before normal mouse-up policy.
- High out-of-bounds submenu mouse-up returns without dismissing the chain; this differs from row `< 0` and should be preserved.
- Parent-forwarded mouse-up uses `handleMouseUp(row, wasDragged: true)`, so policy must preserve row-based `wasDragged` semantics.
- Torn-off menus stay visible for off-row/nonselectable releases; attached menus dismiss the tracking chain.

## Options considered

### Option A: Full mouse event reducer

Move mouse-down, drag, hover, and mouse-up into one reducer-like policy.

Pros:

- Could unify much of the interaction state eventually.

Cons:

- Too broad for this phase.
- Risks moving AppKit/AX/window side effects or introducing behavior drift.
- Would mix ongoing torn-off, hover, drag, and extraction semantics.

### Option B: Mouse-down and mouse-up intent extraction

Extract both press state decisions and release decisions.

Pros:

- Captures a fuller press/release story.

Cons:

- Mouse-down currently opens submenus, consults detached identity helpers, and may run `showSubmenu(for:at:)`; separating pure state from side effects would be larger than needed.
- Higher risk of changing main leaf fallback behavior.

### Option C: Mouse-up-only intent extraction

Extract typed pure intents for `handleMouseUp(_:wasDragged:)` decisions while leaving mouse-down state setup and all side effects in controllers.

Pros:

- Smallest useful Phase 3B slice.
- Builds on the existing `MenuInteractionPolicy` style from Phase 3A.
- Allows focused tests for behavior-sensitive press/release outcomes.
- Keeps side effects and model/AppKit access in controllers.

Cons:

- Leaves some mouse-down branching in controllers for a later phase.
- Requires controller code to compute row facts before calling policy.

Recommendation: **Option C**.

## Proposed API

Extend `Sources/NeXTMenusKit/MenuInteractionState.swift` with mouse-up intent enums and policy functions.

Possible API shape:

```swift
public enum MainMouseUpIntent: Equatable {
    case performTrailingAction(row: Int)
    case collapseAndClearHover
    case deactivateAndClearHover
    case hideAttachedCopy
    case toggleClose
    case keepOpenAndRaiseChain
}

public enum SubmenuMouseUpIntent: Equatable {
    case closeChildClearHoverAndDismissChain
    case closeChildClearHover
    case ignore
    case hideAttachedCopy
    case closeTornOffOpenChild
    case keepAttachedOpenChild
    case closeDraggedOpenChild
    case performLeafAction(clearHover: Bool)
}

public static func mainMouseUpIntent(
    releasedRow: Int,
    pressedRow: Int?,
    pressedRowWasOpen: Bool,
    pressedDetachedSubmenuRow: Int?,
    childSubmenuRow: Int?,
    wasDragged: Bool,
    isSelectable: Bool,
    hasTrailingAction: Bool
) -> MainMouseUpIntent

public static func submenuMouseUpIntent(
    releasedRow: Int,
    pressedOpenSubmenuRow: Int?,
    pressedDetachedSubmenuRow: Int?,
    childSubmenuRow: Int?,
    wasDragged: Bool,
    isTornOff: Bool,
    isInBounds: Bool,
    isSelectable: Bool,
    hasSubmenu: Bool,
    hasElement: Bool
) -> SubmenuMouseUpIntent
```

Exact case names may change during implementation if tests reveal clearer wording. The important boundary is that policy returns declarative intent only; the controller still decides which AppKit/AX/window method to call.

Controller-side facts:

- Main controller computes `hasTrailingAction` using `trailingAction(at:)` but still retrieves and performs the actual action itself after the policy returns `.performTrailingAction(row:)`.
- Main controller computes `isSelectable` only when `releasedRow >= 0`; policy should not force unsafe delegate indexing.
- Submenu controller computes `isInBounds` before indexing `visibleMenuItems`.
- Submenu controller computes `hasElement` from `menuItem.element != nil` only when in bounds.

## Files

Modify:

- `Sources/NeXTMenusKit/MenuInteractionState.swift`
- `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift`
- `Sources/NeXTMenus/MenuWindowController.swift`
- `Sources/NeXTMenus/SubmenuWindowController.swift`

No `NeXTMenus.xcodeproj/project.pbxproj` update is expected because no new source file should be needed.

## Test plan

Add focused tests in `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift` before controller rewiring.

Main mouse-up policy tests:

- Trailing action release returns `performTrailingAction(row:)`.
- Off-row release with open child returns `collapseAndClearHover`.
- Off-row release without open child returns `deactivateAndClearHover`.
- Non-selectable release returns `collapseAndClearHover`.
- High out-of-bounds release is represented as non-selectable input and returns `collapseAndClearHover`, matching the current safe controller behavior after delegate selection fails.
- Matching detached-copy release returns `hideAttachedCopy`.
- Detached-copy release does not match when dragged, released row mismatches, or child row mismatches.
- Toggle-close returns `toggleClose` only when not dragged, pressed row was open, and release row matches pressed row.
- Toggle-close does not happen for drag or row mismatch.
- Normal release returns `keepOpenAndRaiseChain`.

Submenu mouse-up policy tests:

- Off-row attached release returns `closeChildClearHoverAndDismissChain`.
- Off-row torn-off release returns `closeChildClearHover`.
- High out-of-bounds release returns `ignore`.
- Non-selectable attached release returns `closeChildClearHoverAndDismissChain`.
- Non-selectable torn-off release returns `closeChildClearHover`.
- Matching detached-copy submenu release returns `hideAttachedCopy`.
- Attached already-open submenu row release returns `keepAttachedOpenChild`, including when `wasDragged == true`; the pressed-open same-row branch takes precedence over dragged-release close.
- Torn-off already-open submenu row release returns `closeTornOffOpenChild`, including when `wasDragged == true`; the pressed-open same-row branch takes precedence over dragged-release close.
- Dragged release on the currently open submenu row returns `closeDraggedOpenChild` only when `pressedOpenSubmenuRow` is nil or does not match the released/open child row.
- Submenu-capable row otherwise returns `ignore`.
- Leaf row without element returns `ignore`.
- Leaf row with element returns `performLeafAction(clearHover: false)` when attached.
- Leaf row with element returns `performLeafAction(clearHover: true)` when torn off.

Existing tests for open-submenu and attached-copy behavior should remain green.

## Implementation steps

1. Confirm `main` is clean and synced with `origin/main`.
2. Confirm `.worktrees/` is ignored:
   - `git check-ignore .worktrees/`
3. Commit this plan doc on `main` after review and user approval, if the main worktree contains only this doc change.
4. Create dedicated implementation worktree after approval:
   - Branch: `refactor/menu-interaction-press-release`
   - Worktree: `.worktrees/refactor/menu-interaction-press-release/`
5. In the worktree, run baseline checks:
   - `swift test`
6. Add failing policy tests in `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift`.
7. Implement `MainMouseUpIntent`, `SubmenuMouseUpIntent`, and policy functions in `Sources/NeXTMenusKit/MenuInteractionState.swift`.
8. Run focused tests and confirm they pass.
9. Refactor `MenuWindowController.handleMouseUp(_:wasDragged:)`:
   - snapshot and clear controller state as today;
   - compute `hasTrailingAction` and `isSelectable` safely;
   - call `MenuInteractionPolicy.mainMouseUpIntent(...)`;
   - switch over the intent and call existing controller side effects.
10. Refactor `SubmenuWindowController.handleMouseUp(_:wasDragged:)`:
    - preserve snapshot and clearing of `pressedOpenSubmenuRow` and `pressedDetachedSubmenuRow` before `clearHoverForScrollCaretIfNeeded()`;
    - preserve `clearHoverForScrollCaretIfNeeded()` before policy;
    - preserve no deferred chain raise on the scroll-caret early-return path;
    - preserve deferred chain raise for normal mouse-up paths;
    - compute `isInBounds`, `isSelectable`, `hasSubmenu`, and `hasElement` safely;
    - call `MenuInteractionPolicy.submenuMouseUpIntent(...)`;
    - switch over the intent and call existing controller side effects.
11. Run verification:
    - `git diff --check`
    - `make check-sources`
    - `swift test`
    - `swift build`
    - `make verify`
12. Request implementation review before committing the refactor.
13. Commit only Phase 3B files if review passes.
14. Merge to `main` only after automated verification and targeted manual smoke checks.

## Manual verification matrix

Because Phase 3B touches mouse-up interaction decisions, manually verify:

- Main menu: click a row to open a submenu; click the open row again to toggle-close.
- Main menu: click-drag release over submenu parents keeps tracking behavior unchanged.
- Main menu: Hide/Quit/Log Out still fire on release and flash.
- Main menu: release off the menu closes/deactivates as before.
- Attached submenu: already-open submenu row click still no-ops.
- Torn-off submenu: already-open submenu row click closes child on mouse-up and clears highlight.
- Already-torn-off row click at main and nested levels still hides only the temporary attached copy.
- Leaf submenu item click still flashes/performs the AX action/collapses as before.
- Scroll-caret mouse-up still clears press state through the existing early path without installing the normal deferred chain raise.
- Torn-off leaf click still clears hover/highlight before action.
- Parent-forwarded mouse-up from a child still preserves drag-release behavior.
- Recent torn-off validation remains fixed: tear-off dragging up/down does not jump.

## Risks and mitigations

- **Trailing action ordering drift:** keep trailing action intent first, matching current main mouse-up behavior.
- **Unsafe indexing:** compute in-bounds facts before accessing `visibleMenuItems[row]` or delegate selection for submenu rows.
- **Torn-off behavior regression:** preserve different attached/torn-off outcomes for off-row, non-selectable, open-child, and leaf releases.
- **Detached-copy regression:** reuse the existing `shouldHideAttachedCopyOnMouseUp(...)` semantics inside the broader mouse-up policy and keep tests.
- **Main fallback behavior regression:** do not move `showSubmenu(for:at:)` or mouse-down behavior in this phase.
- **Over-broad refactor temptation:** do not extract drag/hover/mouse-down reducers in Phase 3B.
- **Manual-only AppKit behavior:** automated tests cover pure intents; runtime AppKit interaction still needs targeted smoke testing.

## Approval gate

Implementation should not start until:

1. This plan is reviewed.
2. Material concerns are addressed.
3. The user approves creating `refactor/menu-interaction-press-release` and implementing the plan.
