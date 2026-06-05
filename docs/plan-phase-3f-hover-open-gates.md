# Phase 3F Hover Open Gates Plan

## Status

Planning draft. Phase 3F is the next narrow behavior-preserving refactor after Phase 3E. It should not change user-visible interaction semantics.

Phase 3E was merged and pushed as `024e595 refactor: extract drag hover interaction policy`, manual smoke passed, and the Phase 3E worktree/branch were cleaned up before this plan was started.

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

Current pure interaction policy lives in:

- `Sources/NeXTMenusKit/MenuInteractionState.swift`

The remaining pure mouse-move gate logic for Phase 3F is in:

- `Sources/NeXTMenus/MenuWindowController.swift`
  - `handleMouseMoved(_:)`
- `Sources/NeXTMenus/SubmenuWindowController.swift`
  - `handleMouseMoved(_:)`

Existing open-submenu decisions are already pure (`MainOpenSubmenuIntent`, `SubmenuOpenSubmenuIntent`). Phase 3F should extract only the outer mouse-move gate that decides whether to call `updateOpenSubmenu(forHoveredRow:)` after hover/highlight state has been updated.

## Goals

1. Preserve current mouse-move hover-open behavior exactly.
2. Extract pure “should call `updateOpenSubmenu`?” decisions into `NeXTMenusKit`.
3. Keep all state mutation and side effects in controllers.
4. Document main/attached-submenu/torn-off-submenu asymmetries explicitly in tests.
5. Keep Phase 3F small enough to review safely before any broader mouse-event reducer work.

## Non-goals

- No intentional UX changes.
- No full mouse-event reducer.
- No extraction of entire `handleMouseMoved(_:)` handlers.
- No changes to existing open-submenu intent semantics.
- No changes to async drag, mouse-down, mouse-up, reset, highlight, row mapping, scroll-caret, torn-off, detached-submenu, or action execution policies.
- No movement of `childHasMouse`, pointer-enter callbacks, suppress-row-tracking checks, scroll-caret clearing, hover/drag mutations, highlight updates, row/item lookup, window operations, `MenuExtractor`, timers, AppKit/AX, or actions into `NeXTMenusKit`.
- No changes to `MenuExtractor` or `NeXTMenusSettings` placement.

## Current behavior to preserve

### Main `handleMouseMoved(_:)`

Current ordering/effects:

1. If `childHasMouse` is true, set `childHasMouse = false` and update all row highlights.
2. Compute `rowChanged = hoveredRow != row`.
3. If `rowChanged || isDragging`:
   - set `isDragging = false`;
   - set `hoveredRow = row`;
   - update all row highlights.
4. If `rowChanged` and either `childSubmenuRow != nil` or `isMenuActive`, call `updateOpenSubmenu(forHoveredRow: row)`.

Important behavior: the final gate does **not** filter `row >= 0`. If the row changed to `-1` while a child is open or tracking is active, the controller still calls `updateOpenSubmenu(forHoveredRow: -1)`, and the downstream `MainOpenSubmenuIntent` handles the off-row case.

### Submenu `handleMouseMoved(_:)`

Current ordering/effects:

1. Return early when `suppressRowTrackingUntilMouseUp` is true.
2. Return early when `clearHoverForScrollCaretIfNeeded()` handles a scroll-caret row.
3. Call `pointerEnteredSelf()`.
4. Compute `rowChanged = hoveredRow != row`.
5. If `rowChanged || isDragging`:
   - set `isDragging = false`;
   - set `hoveredRow = row`;
   - update all row highlights.
6. If `rowChanged`:
   - for torn-off submenus, call `updateOpenSubmenu(forHoveredRow: row)` only when `childSubmenuRow != nil` and `isSubmenuRow(row)` is true;
   - for attached submenus, always call `updateOpenSubmenu(forHoveredRow: row)`.

Important asymmetries:

- Attached submenus update/open on any row change, including off-row and leaf rows; the existing downstream `SubmenuOpenSubmenuIntent` decides whether to present, close, or ignore.
- Torn-off submenus update/open only when a child submenu is already open and the hovered row is an enabled submenu row. Leaf rows and off-row hovers leave the current open child alone.
- `isSubmenuRow(_:)` stays controller-local because it reads `visibleMenuItems` and encodes controller-facing row/item facts.
- `isSubmenuRow(_:)` must keep its current semantics: in-bounds, has submenu, not a separator, and enabled.
- The `isSubmenuRow(row)` lookup must stay lazily evaluated only after `rowChanged && isTornOff && childSubmenuRow != nil`, preserving the current short-circuiting and avoiding broader visible-item/cache access on same-row, attached, or no-child hovers.

## Options considered

### Option A: Reuse `MainOpenSubmenuIntent` / `SubmenuOpenSubmenuIntent` directly

Pros:

- Avoids adding a small new intent type.

Cons:

- Those intents model what to do after a hover-open update is requested, not whether mouse-move should request one.
- Reuse would obscure main tracking-mode and torn-off gating asymmetries.

Conclusion: reject for Phase 3F.

### Option B: Extract all mouse-move state handling

Pros:

- Could reduce more controller code.

Cons:

- Too broad for this phase.
- Would move or over-model pointer-enter, scroll-caret, hover/drag mutation, and highlight side effects.
- Harder to review behavior preservation.

Conclusion: reject for Phase 3F.

### Option C: Extract only pure hover-open gates

Pros:

- Small and testable.
- Preserves side-effect boundaries.
- Documents the main/attached/torn-off behavior differences clearly.
- Fits the existing narrow-slice refactor pattern.

Cons:

- Controller handlers still perform most work, by design.
- Adds a small intent type for an outer gate.

Recommendation: **Option C**.

## Proposed API

Extend `Sources/NeXTMenusKit/MenuInteractionState.swift` with a shared mouse-move hover-open intent and two policy helpers.

Possible API shape:

```swift
public enum MouseMoveHoverOpenIntent: Equatable {
    case ignore
    case updateOpenSubmenu(row: Int)
}

public static func mainMouseMoveHoverOpenIntent(
    row: Int,
    rowChanged: Bool,
    childSubmenuRow: Int?,
    isMenuActive: Bool
) -> MouseMoveHoverOpenIntent

public static func submenuMouseMoveHoverOpenIntent(
    row: Int,
    rowChanged: Bool,
    isTornOff: Bool,
    childSubmenuRow: Int?,
    hoveredRowIsSubmenuRow: Bool
) -> MouseMoveHoverOpenIntent
```

Exact names may change during implementation if tests reveal clearer wording. The important boundary is that these helpers decide only whether to call `updateOpenSubmenu(forHoveredRow:)`. They must not mutate hover/drag state, update highlights, compute `isSubmenuRow`, close/present submenus, or perform AppKit/AX/window work.

Expected policy rules:

- Main:
  - if `rowChanged == false`, return `.ignore`;
  - if `childSubmenuRow == nil && isMenuActive == false`, return `.ignore`;
  - otherwise return `.updateOpenSubmenu(row: row)`.
- Submenu:
  - if `rowChanged == false`, return `.ignore`;
  - if `isTornOff == false`, return `.updateOpenSubmenu(row: row)`;
  - if torn off, return `.updateOpenSubmenu(row: row)` only when `childSubmenuRow != nil && hoveredRowIsSubmenuRow == true`;
  - otherwise return `.ignore`.

Controller application shape:

- Main `handleMouseMoved(_:)` keeps `childHasMouse`, hover/drag mutations, and highlight updates unchanged, then switches on `mainMouseMoveHoverOpenIntent(...)`.
- Submenu `handleMouseMoved(_:)` keeps suppress-row-tracking, scroll-caret clearing, `pointerEnteredSelf()`, hover/drag mutations, highlight updates, and `isSubmenuRow(row)` lookup in the controller, then switches on `submenuMouseMoveHoverOpenIntent(...)`.
- The submenu controller computes `hoveredRowIsSubmenuRow` lazily only when `rowChanged && isTornOff && childSubmenuRow != nil`; otherwise it passes `false` without touching `visibleMenuItems` through `isSubmenuRow(row)`.
- `updateOpenSubmenu(forHoveredRow:)` remains unchanged in both controllers.

## Files

Modify:

- `Sources/NeXTMenusKit/MenuInteractionState.swift`
- `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift`
- `Sources/NeXTMenus/MenuWindowController.swift`
- `Sources/NeXTMenus/SubmenuWindowController.swift`

No `NeXTMenus.xcodeproj/project.pbxproj` update is expected because no new source file should be needed.

## Test plan

Add focused tests in `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift` before controller rewiring.

Main hover-open gate tests should assert:

- Same-row mouse move returns `.ignore`, even if a child is open or the menu is active.
- Row change with no open child and inactive menu returns `.ignore`.
- Row change with an open child returns `.updateOpenSubmenu(row:)`.
- Row change with an open child and `row == -1` still returns `.updateOpenSubmenu(row: -1)`.
- Row change with no open child but `isMenuActive == true` returns `.updateOpenSubmenu(row:)`.

Submenu hover-open gate tests should assert:

- Same-row mouse move returns `.ignore` for attached and torn-off submenus.
- Attached submenu row change returns `.updateOpenSubmenu(row:)` even when `hoveredRowIsSubmenuRow == false`.
- Attached submenu row change with `row == -1` returns `.updateOpenSubmenu(row: -1)`.
- Torn-off submenu row change returns `.updateOpenSubmenu(row:)` only when a child is open and `hoveredRowIsSubmenuRow == true`.
- Torn-off submenu row change with no child returns `.ignore`.
- Torn-off submenu row change over a leaf/off-row/non-submenu row returns `.ignore`.
- Torn-off submenu row change over a disabled submenu-capable row returns `.ignore` by passing `hoveredRowIsSubmenuRow == false`, preserving existing `isSubmenuRow(_:)` semantics.

Existing open-submenu, async-drag, mouse-up, mouse-down, reset-plan, attached-copy, and highlight policy tests should remain green.

## Implementation steps

1. Confirm `main` is clean and synced with `origin/main`.
2. Confirm `.worktrees/` is ignored:
   - `git check-ignore .worktrees/`
3. Commit this plan doc on `main` after review and user approval, if the main worktree contains only this doc change.
4. Create dedicated implementation worktree after approval:
   - Branch: `refactor/menu-interaction-hover-open-gates`
   - Worktree: `.worktrees/refactor/menu-interaction-hover-open-gates/`
5. In the worktree, run baseline checks:
   - `swift test`
6. Add failing hover-open gate tests in `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift`.
7. Implement `MouseMoveHoverOpenIntent`, `mainMouseMoveHoverOpenIntent(...)`, and `submenuMouseMoveHoverOpenIntent(...)` in `Sources/NeXTMenusKit/MenuInteractionState.swift`.
8. Run focused tests and confirm they pass:
   - `swift test --filter MenuInteractionStateTests`
9. Refactor `MenuWindowController.handleMouseMoved(_:)` to use the main gate while preserving ordering and side effects.
10. Refactor `SubmenuWindowController.handleMouseMoved(_:)` to use the submenu gate while preserving ordering and side effects.
11. Run verification:
    - `git diff --check`
    - `make check-sources`
    - `swift test`
    - `swift build`
    - `make verify`
12. Request implementation review before committing the refactor.
13. Commit only Phase 3F files if review passes.
14. Merge to `main` only after automated verification and targeted manual smoke checks or explicit user instruction to proceed.

## Manual verification matrix

Because Phase 3F touches mouse-move hover-open gating, manually verify:

- Main menu: hovering sibling submenu items while a submenu is open still switches the open submenu.
- Main menu: hovering off the rows while a submenu is open still preserves/clears exactly as before through existing downstream intent behavior.
- Main menu: click-open tracking mode still lets later submenu hovers open after a trailing-action hover closes the child.
- Attached submenu: plain hover still opens/switches submenus freely.
- Attached submenu: hovering leaf/off-row still closes or ignores according to existing downstream behavior.
- Torn-off submenu: hovering a submenu row while a child is open still switches to that submenu.
- Torn-off submenu: hovering leaf/off-row while a child is open still leaves the open child alone.
- Existing Phase 3E drag-hover behavior remains unchanged.

## Risks and mitigations

- **Off-row filtering regression:** do not add row validity checks to the new gate; existing downstream intents handle `row == -1`.
- **Torn-off behavior regression:** preserve the stricter torn-off condition requiring an open child and a submenu-capable hovered row.
- **Side-effect movement:** keep pointer, scroll-caret, hover/drag mutation, highlights, row/item lookup, and submenu presentation/closing in controllers.
- **Lookup timing drift:** compute `isSubmenuRow(row)` only under the current torn-off row-change/open-child gates so same-row, attached, and no-child hovers do not gain visible-item/cache lookup side effects.
- **Confusing gate with action:** the new intent decides only whether to call `updateOpenSubmenu`; it must not choose close/present/show behavior.
- **False confidence from pure tests:** policy tests cover gate decisions; implementation review must still check controller ordering and side-effect boundaries.

## Approval gate

Implementation should not start until:

1. This plan is reviewed.
2. Material concerns are addressed.
3. The user approves committing this plan, creating `refactor/menu-interaction-hover-open-gates`, and implementing the plan.
