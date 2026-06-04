# Phase 3A Interaction State Plan

## Status

Planning draft. User chose a narrow Phase 3A first: extract only the pure `updateOpenSubmenu(forHoveredRow:)` transition decisions. A full mouse-event reducer and reset/collapse state helpers are deferred to later slices.

## Context

Completed groundwork on `main`:

- `3838984 chore: add Xcode build workflow and tests`
- `4b11d3d refactor: extract main menu row mapping`
- `b1a5d6b docs: update phase two refactor plan`
- `55891fa refactor: extract menu highlight policy`
- `765b814 fix: stabilize submenu row clicks`

The remaining interaction complexity is concentrated in:

- `Sources/NeXTMenus/MenuWindowController.swift`
- `Sources/NeXTMenus/SubmenuWindowController.swift`

Phase 1 extracted pure main-menu row mapping to `NeXTMenusKit`.
Phase 2 extracted pure row highlight predicates to `NeXTMenusKit`.
Phase 3A should continue that pattern by extracting only pure submenu-open transition decisions, leaving AppKit, AX, windows, callbacks, timers, and extraction side effects in controllers.

## Goals

1. Preserve behavior exactly while reducing controller branching in `updateOpenSubmenu(forHoveredRow:)`.
2. Add focused tests for main-menu and submenu open/close decision behavior.
3. Introduce a tiny `NeXTMenusKit` interaction policy that returns declarative intents.
4. Keep controller side effects explicit and local.
5. Make later Phase 3 slices safer by establishing tested interaction-decision vocabulary.

## Non-goals

- No intentional UX changes.
- No full mouse event reducer in Phase 3A.
- No movement of `handleMouseMoved`, `handleMouseDown`, `handleMouseDragged`, or `handleMouseUp` wholesale.
- No extraction of reset/collapse state clearing helpers; defer to Phase 3B.
- No changes to submenu lifecycle ownership, child controller creation, callbacks, window ordering, timers, AX action execution, scrolling, or torn-off window mechanics.
- No movement of `MenuExtractor` or `NeXTMenusSettings` into `NeXTMenusKit`.

## Current behavior to preserve

### Main menu

Current decision logic lives in `MenuWindowController.updateOpenSubmenu(forHoveredRow:)`.

Behavior and ordering:

- Row `< 0`: ignore; keep any open submenu because the pointer may be crossing deadspace into a child window.
- Row beyond the known table/model range: ignore; preserve any currently open child.
- Hovering the already-open child row: ignore, even if `isDragging == true`.
- Non-selectable row: ignore.
- Trailing action row:
  - If a child submenu is open, collapse it with `endsTracking: false` so click-open tracking remains active.
  - This trailing-action rule must win over the drag-with-open-child rule, including while `isDragging == true`.
  - If no child submenu is open, ignore.
- Dragging while a child submenu is already open and hovering a sibling row:
  - collapse submenus with default `endsTracking: true`.
  - Do not switch to the sibling submenu.
- Dragging with no open child follows the normal row behavior.
- Selectable non-separator menu item row:
  - show that row's submenu or execute fallback behavior through existing controller methods.
  - Preserve current `hasMenuItem` semantics rather than changing to `hasSubmenu`; `showSubmenu(for:at:)` is still the controller-owned path that may perform fallback behavior when extracted submenu contents are empty.

### Submenu

Current decision logic lives in `SubmenuWindowController.updateOpenSubmenu(forHoveredRow:)`.

Behavior and ordering:

- Row `< 0`: ignore; keep any open submenu because the pointer may be crossing deadspace into a child window.
- Hovering the already-open child row: ignore, even if `isDragging == true`.
- Dragging while a child submenu is already open and hovering a sibling row:
  - close the current child submenu.
  - update highlights.
  - Do not switch to the sibling submenu.
- Dragging with no open child follows the normal row behavior.
- Selectable, in-bounds, non-separator submenu row with a submenu:
  - present that submenu.
- Hovering a leaf, separator, disabled, or high out-of-bounds row while a child submenu is open:
  - close the current child submenu and update highlights.
- Same leaf/invalid hover with no child submenu open:
  - ignore.

Controller rewiring must compute `isInBounds` before calling `tableView(_:shouldSelectRow:)` or indexing `visibleMenuItems[row]`, because the current submenu delegate indexes `visibleMenuItems[row]` directly.

Important surrounding behavior that Phase 3A must not change:

- Main plain hover only calls `updateOpenSubmenu` once a child submenu is open or click-open tracking mode is active.
- Attached submenu plain hover calls `updateOpenSubmenu` freely.
- Torn-off submenu plain hover calls `updateOpenSubmenu` only when an open child exists and the hovered row is itself a submenu row.
- Submenu drag calls `updateOpenSubmenu` on every drag, not only when row changes.
- Main drag uses `openSubmenuFromDragAsync(forRow:)`, not only `updateOpenSubmenu`; Phase 3A should not rewrite async extraction.

## Proposed API

Add a small pure file:

- `Sources/NeXTMenusKit/MenuInteractionState.swift`

Initial API shape:

```swift
public enum MainOpenSubmenuIntent: Equatable {
    case ignore
    case collapse(endsTracking: Bool)
    case showSubmenu(row: Int)
}

public enum SubmenuOpenSubmenuIntent: Equatable {
    case ignore
    case close
    case present(row: Int)
}

public enum MenuInteractionPolicy {
    public static func mainOpenSubmenuIntent(
        hoveredRow: Int,
        childSubmenuRow: Int?,
        isSelectable: Bool,
        isTrailingAction: Bool,
        isDragging: Bool,
        hasMenuItem: Bool,
        isSeparator: Bool
    ) -> MainOpenSubmenuIntent

    public static func submenuOpenSubmenuIntent(
        hoveredRow: Int,
        childSubmenuRow: Int?,
        isDragging: Bool,
        isSelectable: Bool,
        isInBounds: Bool,
        isSeparator: Bool,
        hasSubmenu: Bool
    ) -> SubmenuOpenSubmenuIntent
}
```

Rationale:

- Separate main/submenu entry points keep behavior differences explicit.
- Inputs are primitive row facts computed by controllers from current AppKit/model state.
- The policy does not know about `MenuItem`, `NSTableView`, `MenuExtractor`, windows, callbacks, timers, or highlights.
- Intents describe what the controller should do, without performing side effects.

The exact enum/type names can be adjusted during implementation if tests reveal a clearer shape, but the Phase 3A boundary should remain narrow.

## Files

Add:

- `Sources/NeXTMenusKit/MenuInteractionState.swift`
- `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift`

Modify:

- `NeXTMenus.xcodeproj/project.pbxproj`
- `Sources/NeXTMenus/MenuWindowController.swift`
- `Sources/NeXTMenus/SubmenuWindowController.swift`

## Test plan

Add focused characterization tests before controller rewiring.

Main menu policy tests:

- Off-row hover ignores and preserves open submenu.
- High out-of-bounds row ignores and preserves open submenu.
- Hovering the already-open child row ignores, including while dragging.
- Non-selectable row ignores.
- Trailing action with open child collapses with `endsTracking: false`.
- Trailing action with open child while dragging still collapses with `endsTracking: false`, not the drag default.
- Trailing action without open child ignores.
- Dragging with an open child over a sibling collapses with `endsTracking: true`.
- Dragging with no open child over a normal row returns `showSubmenu(row:)`.
- Selectable normal row with menu item returns `showSubmenu(row:)`.
- Separator or missing menu item ignores.
- Normal rows use `hasMenuItem`, not `hasSubmenu`, so controller fallback behavior remains reachable.

Submenu policy tests:

- Off-row hover ignores and preserves open submenu.
- Hovering the already-open child row ignores, including while dragging.
- Dragging with an open child over a sibling closes only the current child.
- Dragging with no open child over a submenu row returns `present(row:)`.
- Selectable in-bounds submenu row returns `present(row:)`.
- Leaf row with open child closes.
- Leaf row without open child ignores.
- Separator, disabled, or high out-of-bounds row with open child closes.
- Separator, disabled, or high out-of-bounds row without open child ignores.
- High out-of-bounds policy cases do not require controller indexing and must be paired with controller rewiring that checks bounds before `shouldSelectRow`.

Controller integration checks by inspection and tests:

- Existing calls to `showSubmenu`, `presentSubmenu`, `collapseSubmenus`, `closeSubmenu`, and `updateAllRowHighlights` remain in controllers.
- No behavior is moved into `NeXTMenusKit` that requires AppKit/AX/window access.

## Implementation steps

1. Confirm repo status on `main`.
2. Resolve the planning document before implementation worktree creation:
   - preferred: commit `docs/plan-phase-3-interaction-state.md` as a docs-only commit after plan review/user approval if safe; or
   - explicitly stash/carry the plan doc, or create the implementation worktree only after the main worktree is clean.
3. Confirm `.worktrees/` is ignored with `git check-ignore .worktrees/`.
4. Create dedicated worktree:
   - Branch: `refactor/menu-interaction-open-policy`
   - Worktree: `.worktrees/refactor/menu-interaction-open-policy/`
5. Run baseline checks in that worktree:
   - `swift test`
   - optionally `make verify` if baseline confidence is needed before editing.
6. Add failing tests in `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift` for the policy matrix above.
7. Add `Sources/NeXTMenusKit/MenuInteractionState.swift` with pure intent enums and policy functions.
8. Update `NeXTMenus.xcodeproj/project.pbxproj` to include the new source file in the app target source list.
9. Refactor `MenuWindowController.updateOpenSubmenu(forHoveredRow:)` to:
   - compute row facts from current controller helpers;
   - call `MenuInteractionPolicy.mainOpenSubmenuIntent(...)`;
   - switch over the returned intent and perform existing controller side effects.
10. Refactor `SubmenuWindowController.updateOpenSubmenu(forHoveredRow:)` similarly, with `isInBounds` computed before any delegate call or `visibleMenuItems[row]` indexing.
11. Run verification:
    - `git diff --check`
    - `make check-sources`
    - `swift test`
    - `swift build`
    - `make verify`
12. Request implementation review before commit.
13. Commit only the Phase 3A files if review passes.

## Manual verification matrix

Because Phase 3A touches interaction decisions, manually check:

- Main menu: plain hover still does not open submenus before tracking is active.
- Main menu: click a row to open a submenu.
- Main menu: hover sibling while submenu is open switches as before.
- Main menu: hover Hide/Quit/Log Out while a submenu is open closes the child but preserves tracking.
- Main menu: click-drag behavior over sibling rows remains unchanged.
- Attached submenu: hover opens/switches child submenus.
- Attached submenu: hover leaf while child is open closes child.
- Torn-off submenu: leaf hover behavior remains unchanged.
- Torn-off submenu: child submenu row hover behavior remains unchanged.
- Recently fixed submenu click behavior remains unchanged:
  - attached already-open submenu row click no-ops;
  - torn-off already-open submenu row click closes child on mouse-up and clears highlight.

## Risks and mitigations

- **Behavior drift in drag switching:** tests must separately cover main and submenu drag-with-open-child cases because they intentionally collapse instead of switch.
- **Main tracking mode regression:** trailing actions must use `collapse(endsTracking: false)`, not default collapse.
- **Torn-off behavior confusion:** Phase 3A should not move the torn-off gating in `handleMouseMoved`; only the decision made after `updateOpenSubmenu` is called.
- **Async drag-open confusion:** main `openSubmenuFromDragAsync(forRow:)` is out of scope.
- **Over-broad reducer temptation:** do not move mouse event handlers in this slice.
- **Xcode source drift:** update `project.pbxproj` and run `make check-sources`.

## Review gate

Before implementation approval, review this plan for:

- exact Phase 3A boundary;
- behavior-preserving coverage;
- side-effect boundaries;
- test matrix completeness;
- worktree strategy;
- verification commands.
