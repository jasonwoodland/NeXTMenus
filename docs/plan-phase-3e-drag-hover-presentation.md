# Phase 3E Drag Hover Presentation Plan

## Status

Planning draft. Phase 3E is the next narrow behavior-preserving refactor after Phase 3D. It should not change user-visible interaction semantics.

Phase 3D was merged and pushed as `53f6c7d refactor: extract reset interaction policy`, and manual smoke passed before this plan was started.

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

Current pure interaction policy lives in:

- `Sources/NeXTMenusKit/MenuInteractionState.swift`

Current controller drag-hover submenu presentation logic is concentrated in:

- `Sources/NeXTMenus/MenuWindowController.swift`
  - `handleMouseDragged(_:)`
  - `openSubmenuFromDragAsync(forRow:)`
  - `showSubmenu(for:at:submenuItems:fallbackElement:)`
  - `collapseSubmenus(endsTracking:)`

The submenu-window drag path already uses synchronous pure open-submenu intent through `SubmenuOpenSubmenuIntent`. The main-window drag path is different: it asynchronously extracts submenu items away from the mouse-tracking call stack, then presents only if the original drag hover is still current.

## Goals

1. Preserve current main drag-hover submenu behavior exactly.
2. Extract only pure main async-drag preflight and completion decisions into `NeXTMenusKit`.
3. Keep async generation mutation and cancellation semantics in `MenuWindowController`.
4. Keep `DispatchQueue`, `MenuExtractor`, AppKit/window presentation, collapse/show calls, highlight updates, and drag-hover restoration in `MenuWindowController`.
5. Add focused pure tests for main async-drag decisions and completion gating.
6. Keep Phase 3E small enough to review safely before any broader mouse-event reducer work.

## Non-goals

- No intentional UX changes.
- No full mouse-event reducer.
- No extraction of `handleMouseDragged(_:)` as a whole.
- No extraction of submenu-window drag behavior.
- No movement of `DispatchQueue`, `MenuExtractor`, `showSubmenu`, `collapseSubmenus`, window creation/reconfiguration, AX actions, timers, callbacks, table updates, or AppKit state into `NeXTMenusKit`.
- No changes to row mapping, highlight rendering, mouse-down/up policies, reset plans, detached submenu retention, torn-off z-order, or app-switch hiding behavior.
- No fallback action execution from the async drag path.

## Current behavior to preserve

### `handleMouseDragged(_:)`

Current ordering/effects in `MenuWindowController`:

1. If the pointer is over a main-menu row and `childHasMouse` is true, set `childHasMouse = false` and update highlights.
2. Compute whether the hover row changed.
3. If the row changed or dragging was not already active:
   - set `isDragging = true`;
   - set `hoveredRow = row`;
   - update highlights.
4. Always call `openSubmenuFromDragAsync(forRow: row)` so a submenu can re-open after a click-drag toggle closed it.

Phase 3E should not refactor this outer ordering beyond the narrow call to a pure decision inside `openSubmenuFromDragAsync(forRow:)`.

### `openSubmenuFromDragAsync(forRow:)`

Current ordering/effects:

1. Increment `asyncSubmenuOpenGeneration`.
2. Capture the incremented generation.
3. If `row < 0`, return. This still cancels pending async opens because generation was already incremented.
4. Validate that all of the following are true:
   - `childSubmenuRow != row`;
   - the table delegate allows selecting `row`;
   - `mainMenuItem(at: row)` returns a menu item;
   - the menu item is not a separator;
   - the menu item has a submenu.
5. If validation fails and there is an open child at a different row:
   - call `collapseSubmenus(endsTracking: false)`;
   - restore `hoveredRow = row`;
   - restore `isDragging = true`;
   - update highlights.
6. If validation fails and there is no different open child, return.
7. If validation succeeds, extract submenu items on a background queue using `MenuExtractor.submenuItems(for:)`.
8. On the main queue, present only if:
   - the captured generation still matches `asyncSubmenuOpenGeneration`;
   - `isDragging` is still true;
   - `hoveredRow == row`.
9. If completion remains valid, call `showSubmenu(for:at:submenuItems:fallbackElement: nil)`.

Important asymmetry: unlike click presentation, the async drag path passes `fallbackElement: nil`. If extracted submenu items are empty, it should not execute a fallback AX action.

Important ordering: every call to `openSubmenuFromDragAsync(forRow:)` increments `asyncSubmenuOpenGeneration` before any row validation. Phase 3E must preserve this cancellation behavior.

## Options considered

### Option A: Reuse `mainOpenSubmenuIntent(...)`

Pros:

- Reuses an existing policy API.

Cons:

- Main drag async semantics differ from hover-open semantics.
- Existing hover-open drag behavior collapses with `endsTracking: true` in some cases, while async drag invalid-row collapse preserves tracking with `endsTracking: false` and restores drag hover state.
- The async completion generation gate has no equivalent in `mainOpenSubmenuIntent(...)`.

Conclusion: reject for Phase 3E.

### Option B: Extract the whole drag handler

Pros:

- Could reduce more controller code.

Cons:

- Too broad for this phase.
- Would risk moving highlight, child-mouse, and controller-owned mutable state semantics into the kit.
- Harder to review behavior preservation.

Conclusion: reject for Phase 3E.

### Option C: Pure async-drag preflight intent and completion validator

Pros:

- Small, behavior-preserving, and testable.
- Keeps side effects and mutation in the controller.
- Documents async drag semantics separately from hover-open semantics.
- Makes later reducer work safer without doing it now.

Cons:

- Controller still performs all mutation and side effects.
- The policy has another main-specific intent type.

Recommendation: **Option C**.

## Proposed API

Extend `Sources/NeXTMenusKit/MenuInteractionState.swift` with a main async-drag intent and completion validator.

Possible API shape:

```swift
public enum MainAsyncDragSubmenuIntent: Equatable {
    case ignore
    case startAsyncOpen(row: Int)
    case collapseCurrentChildPreservingTracking(row: Int)
}

public static func mainAsyncDragSubmenuIntent(
    row: Int,
    childSubmenuRow: Int?,
    isSelectable: Bool,
    hasMenuItem: Bool,
    isSeparator: Bool,
    hasSubmenu: Bool
) -> MainAsyncDragSubmenuIntent

public static func shouldPresentMainAsyncDragSubmenu(
    requestedGeneration: Int,
    currentGeneration: Int,
    isDragging: Bool,
    hoveredRow: Int?,
    requestedRow: Int
) -> Bool
```

Exact names may change during implementation if tests reveal clearer wording. The important boundary is that the policy returns pure decisions only; it must not increment generations, extract menus, dispatch queues, show/collapse windows, restore hover state, or update highlights.

Controller application shape:

- `openSubmenuFromDragAsync(forRow:)` still increments `asyncSubmenuOpenGeneration` before calling the policy.
- The controller computes existing input facts lazily and explicitly:
  - row validity/selectability via the table delegate;
  - `mainMenuItem(at:)`;
  - separator and submenu flags.
- For `.ignore`, return.
- For `.collapseCurrentChildPreservingTracking(row)`, the controller performs the existing side effects:
  - `collapseSubmenus(endsTracking: false)`;
  - restore `hoveredRow = row`;
  - restore `isDragging = true`;
  - `updateAllRowHighlights()`.
- For `.startAsyncOpen(row)`, the controller performs the existing async extraction and completion dispatch.
- Completion dispatch calls the pure validator before `showSubmenu(...)`.

## Files

Modify:

- `Sources/NeXTMenusKit/MenuInteractionState.swift`
- `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift`
- `Sources/NeXTMenus/MenuWindowController.swift`

No `SubmenuWindowController.swift` change is expected for Phase 3E.

No `NeXTMenus.xcodeproj/project.pbxproj` update is expected because no new source file should be needed.

## Test plan

Add focused tests in `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift` before controller rewiring.

Preflight intent tests should assert:

- Off-row (`row < 0`) returns `.ignore`, relying on the controller to have already cancelled pending async via generation increment.
- A row whose child submenu is already open returns `.ignore`.
- A row whose child submenu is already open still returns `.ignore` even if later validity facts are false; `childSubmenuRow == row` must take precedence over invalid row/item/submenu facts.
- A valid selectable non-separator submenu row returns `.startAsyncOpen(row:)`.
- A valid selectable submenu sibling returns `.startAsyncOpen(row:)` even when a different child submenu is already open; the controller must not pre-collapse the old child before async extraction completes.
- Invalid rows with a different open child return `.collapseCurrentChildPreservingTracking(row:)`, including:
  - non-selectable/disabled row;
  - missing menu item or trailing-action row;
  - separator row;
  - leaf row where `hasSubmenu == false`.
- The same invalid rows with no open child return `.ignore`.
- `hasSubmenu == false` never returns `.startAsyncOpen`, preserving the no-fallback-action async drag behavior.

Completion validator tests should assert:

- Matching generation, active dragging, and matching hover row returns `true`.
- Stale generation returns `false`.
- Ended dragging returns `false`.
- Moved hover row returns `false`.
- Nil hover row returns `false`.

Existing open-submenu, mouse-up, mouse-down, reset-plan, attached-copy, and highlight policy tests should remain green.

## Implementation steps

1. Confirm `main` is clean and synced with `origin/main`.
2. Confirm `.worktrees/` is ignored:
   - `git check-ignore .worktrees/`
3. Commit this plan doc on `main` after review and user approval, if the main worktree contains only this doc change.
4. Create dedicated implementation worktree after approval:
   - Branch: `refactor/menu-interaction-drag-hover`
   - Worktree: `.worktrees/refactor/menu-interaction-drag-hover/`
5. In the worktree, run baseline checks:
   - `swift test`
6. Add failing async-drag intent and completion-validator tests in `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift`.
7. Implement `MainAsyncDragSubmenuIntent`, `mainAsyncDragSubmenuIntent(...)`, and `shouldPresentMainAsyncDragSubmenu(...)` in `Sources/NeXTMenusKit/MenuInteractionState.swift`.
8. Run focused tests and confirm they pass:
   - `swift test --filter MenuInteractionStateTests`
9. Refactor `MenuWindowController.openSubmenuFromDragAsync(forRow:)` to use the pure intent and completion validator while preserving:
   - generation increment before validation;
   - return behavior for off-row/current-child rows;
   - collapse with `endsTracking: false` for invalid rows with a different open child;
   - hover/drag restoration after collapse;
   - background extraction with `MenuExtractor`;
   - main-queue completion guard semantics using live controller facts at completion time;
   - no pre-collapse for valid sibling submenu rows;
   - `fallbackElement: nil`.
10. Run verification:
    - `git diff --check`
    - `make check-sources`
    - `swift test`
    - `swift build`
    - `make verify`
11. Request implementation review before committing the refactor.
12. Commit only Phase 3E files if review passes.
13. Merge to `main` only after automated verification and targeted manual smoke checks or explicit user instruction to proceed.

## Manual verification matrix

Because Phase 3E touches drag-hover submenu presentation, manually verify:

- Main menu: click-drag over a submenu row still opens that submenu after extraction completes.
- Main menu: rapidly dragging across submenu siblings leaves only the latest hovered submenu open.
- Main menu: dragging off rows cancels pending async opens without closing an already-open child solely because the pointer left the table.
- Main menu: dragging over a leaf/trailing/disabled/separator row with an open child collapses the child but keeps drag tracking/highlight active.
- Main menu: dragging over a leaf/trailing/disabled/separator row without an open child does not execute an action.
- Main menu: dragging back to a submenu row after a click-drag toggle can re-open it.
- Existing torn-off drag behavior remains fixed: tearing off up/down does not jump.
- Existing torn-off/open-child row mouse-up behavior remains unchanged.

## Risks and mitigations

- **Generation ordering drift:** increment `asyncSubmenuOpenGeneration` before any policy call or row validation.
- **Hover-open semantics confusion:** do not reuse `mainOpenSubmenuIntent(...)`; async drag has distinct collapse and completion behavior.
- **Side-effect movement:** keep `DispatchQueue`, `MenuExtractor`, window presentation, collapse/show, hover restoration, and highlights in the controller.
- **Fallback action regression:** async drag must continue passing `fallbackElement: nil` and must not execute leaf actions.
- **Already-open row regression:** `childSubmenuRow == row` must continue no-oping before invalid row facts can cause collapse.
- **Valid sibling flicker/regression:** valid sibling submenu rows must start async extraction without pre-collapsing the current child; stale completions should leave the old child intact.
- **False confidence from pure tests:** policy tests cover decisions; implementation review must still check controller ordering and side-effect boundaries.

## Approval gate

Implementation should not start until:

1. This plan is reviewed.
2. Material concerns are addressed.
3. The user approves committing this plan, creating `refactor/menu-interaction-drag-hover`, and implementing the plan.
