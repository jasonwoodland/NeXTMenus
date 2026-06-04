# Torn-Off Menu Behavior Fix Plan

## Status

Draft design/plan. User feedback identified three torn-off menu behavior issues:

1. Torn-off menus should have a z-index lower than the application's main NeXTMenus menu.
2. Torn-off menus should only be visible for the active target application.
3. Clicking a menu item whose submenu is already torn off should hide the temporary non-torn-off copy on mouse-up.

Accepted behavior decisions:

- Torn-off menus should still stay above normal target app windows, but below NeXTMenus main/attached menu windows.
- Already-torn-off row click handling applies at every menu-chain level: main menu rows and nested submenu rows.
- When the target app is no longer active, torn-off submenu windows should order out; when the same target app becomes active again, they should reappear in their previous torn-off positions unless the user closed them.

## Context

Current relevant files:

- `Sources/NeXTMenus/MenuWindowController.swift`
- `Sources/NeXTMenus/SubmenuWindowController.swift`
- `Sources/NeXTMenus/ApplicationObserver.swift`
- `Sources/NeXTMenusKit/MenuInteractionState.swift`
- `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift`

Current behavior observed in code:

- `MenuWindowController.setupWindow` uses `.popUpMenu` for the main window.
- `SubmenuWindowController.setupWindow` also uses `.popUpMenu` for submenu windows.
- `SubmenuWindowController.windowDidMove(_:)` marks `isTornOff = true` after the drag threshold and shows the close button, but does not lower the window level.
- `SubmenuWindowController.activeApplicationChanged(_:)` already orders torn-off windows out when their target app is not frontmost and orders them front again when the target app is frontmost, unless `userClosed` is true.
- Both `MenuWindowController.makeChildController(...)` and `SubmenuWindowController.makeChildController(...)` append a torn-off child to `detachedControllers` and clear `childSubmenuController`/`childSubmenuRow`.
- Because parent row state is cleared after tear-off, a later click on the same row creates a new attached submenu copy. Existing pressed-open tracking only knows about attached children (`pressedRowWasOpen` / `pressedOpenSubmenuRow`), so mouse-up does not hide that temporary attached copy.

## Goals

1. Keep torn-off submenu windows visually above ordinary app windows but below the active NeXTMenus main/attached menu chain.
2. Make active-app-only visibility explicit and robust for torn-off submenu windows.
3. Preserve torn-off submenu state and position across app switches.
4. Hide only the temporary attached copy on mouse-up when clicking a row whose submenu is already torn off.
5. Apply the already-torn-off row behavior at both main-menu and nested-submenu levels.
6. Keep this as a focused behavior bugfix; do not fold it into a broader interaction reducer.

## Non-goals

- No full mouse event reducer.
- No reset/collapse helper extraction.
- No changes to row mapping, highlight policy, scrolling, rendering layout, AX action execution, or menu extraction.
- No change to the existing rule that attached transient menu windows use the higher menu level.
- No change to torn-off close-button semantics: a user-closed torn-off menu should not resurrect on app switch.
- No attempt to make AppKit window-level behavior fully unit-testable.

## Proposed design

### 1. Torn-off window level

Use two explicit submenu levels in `SubmenuWindowController`:

- attached submenu level: `.popUpMenu`
- torn-off submenu level: a lower floating level, likely `.floating`

Behavior:

- New/attached submenu windows remain at `.popUpMenu`.
- When `windowDidMove(_:)` marks a submenu as torn off, immediately set that window's level to the torn-off level.
- When an attached submenu is shown or reused via `showWindow(rightOf:alignedToRow:)`, explicitly reset it to the attached submenu level (`.popUpMenu`) before ordering it front.
- When a torn-off submenu is restored after target app activation, restore it at the torn-off level before ordering it front.

Rationale:

- `.popUpMenu` keeps main/attached menu chains above normal app windows.
- `.floating` keeps torn-off menus above ordinary app windows while letting `.popUpMenu` NeXTMenus windows appear above them.

### 2. Active-app-only torn-off visibility

Keep using `NSWorkspace.didActivateApplicationNotification` inside `SubmenuWindowController`, but make the behavior explicit in a helper such as:

```swift
private func updateTornOffVisibilityForFrontmostApplication()
```

Behavior:

- If `isTornOff == false`, do nothing.
- If `userClosed == true`, do nothing / remain closed.
- If `frontmostApplication.processIdentifier == targetApp?.processIdentifier`:
  - set torn-off level;
  - order the torn-off window front at its existing frame.
- Otherwise:
  - order the torn-off window out;
  - explicitly hide and clear any visible transient **non-torn-off** child chain attached to that torn-off window, for example via `childSubmenuController?.hideWindow(animated: false)` plus row/highlight cleanup, so no attached copy remains visible for the inactive app;
  - let any independently torn-off descendants manage their own visibility/restoration through their own active-app observer.

Implementation should be careful not to destroy torn-off state or change the saved frame. Ordering out/in should preserve existing torn-off window frames. Restoring on activation should restore only torn-off windows whose `userClosed` flag is false.

### 3. Already-torn-off row click handling

Track detached submenu ownership by source row **and parent item identity** in both parent controllers. Row-only identity is not sufficient because modifier filtering, full-menu refreshes, or settings changes can shift rows while detached windows remain alive.

Current `detachedControllers: [SubmenuWindowController]` is append-only. Replace or augment it with a small parent-local record, for example:

```swift
private struct DetachedSubmenuReference {
    let sourceRow: Int
    let identity: DetachedSubmenuIdentity
    let controller: SubmenuWindowController
}

private struct DetachedSubmenuIdentity {
    let title: String
    let keyEquivalent: String?
    let isSeparator: Bool
    let element: AXUIElement?
}
```

Identity matching should prefer AX identity when both sides have elements, using `CFEqual(lhs, rhs)`, then fall back to stable menu-item attributes such as title, shortcut, and separator/submenu kind. Keep this helper in the app target; do not move AX concepts into `NeXTMenusKit`.

In both `MenuWindowController` and `SubmenuWindowController`:

- When `onTornOff` fires, capture the current `childSubmenuRow` and current parent menu item identity before clearing row/controller state.
- Store `(sourceRow, identity, child)`.
- Add helper logic to check whether the pressed row currently has a restorable detached submenu with matching source row and current item identity.
- Ignore/prune references whose controller was user-closed.

Expose only the minimum state needed from `SubmenuWindowController`, such as:

```swift
var isRestorableDetachedMenu: Bool { isTornOff && !userClosed }
```

Mouse handling behavior:

- On mouse-down for a submenu-capable row, record whether that row already has a restorable detached submenu with matching current item identity.
- Preserve current mousedown behavior that may open a temporary attached copy.
- On matching mouse-up with no drag, run the detached-copy policy before the existing attached-open-row toggle/no-op branches, including before `pressedOpenSubmenuRow` handling in nested submenus.
- If the policy matches:
  - hide/collapse only the temporary attached copy;
  - leave the torn-off copy alive and visible if the target app is active;
  - clear hover/highlight state as the existing collapse/close path does.

Main menu implementation shape:

- Add state such as `pressedRowHadDetachedSubmenu` or `pressedDetachedSubmenuRow`.
- Set it in `handleMouseDown(_:)` before opening the row's attached submenu copy.
- In `handleMouseUp(_:wasDragged:)`, after selectability checks and before normal click-drag release behavior, if the same row was pressed and it had a detached submenu, call `collapseSubmenus()` and return.

Submenu implementation shape:

- Add analogous `pressedDetachedSubmenuRow` state.
- Set it in `handleMouseDown(_:)` before opening the row's attached submenu copy.
- In `handleMouseUp(_:wasDragged:)`, when releasing the same submenu-capable row, call `closeSubmenu()` and `updateAllRowHighlights()` if the row had a detached submenu; do not call `dismissChain?()` and do not close the torn-off copy.

### 4. Pure decision test surface

Window levels and app activation are AppKit/runtime behavior and should be manually verified. The mouse-up decision can still get focused unit coverage by adding a tiny pure policy to `MenuInteractionPolicy`, for example:

```swift
public static func shouldHideAttachedCopyOnMouseUp(
    pressedDetachedSubmenuRow: Int?,
    releasedRow: Int,
    childSubmenuRow: Int?,
    wasDragged: Bool
) -> Bool
```

Expected behavior:

- returns true only when:
  - `wasDragged == false`,
  - `pressedDetachedSubmenuRow == releasedRow`, and
  - `childSubmenuRow == releasedRow`.
- returns false for drag release, mismatched release row, mismatched child row, no detached row, or no temporary attached child.

## Files

Likely modified:

- `Sources/NeXTMenus/SubmenuWindowController.swift`
- `Sources/NeXTMenus/MenuWindowController.swift`
- `Sources/NeXTMenusKit/MenuInteractionState.swift`
- `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift`

No new source file is expected unless implementation evidence shows the helper logic should be separated.

## Test plan

Automated tests:

- Extend `MenuInteractionStateTests` to cover `shouldHideAttachedCopyOnMouseUp(...)`:
  - matching pressed-detached row, release row, and child row returns true;
  - drag release returns false;
  - mismatched release row returns false;
  - mismatched child row returns false;
  - missing child row returns false;
  - no pressed detached row returns false.

Static/inspection checks:

- `SubmenuWindowController` uses attached level for attached submenus and torn-off level for `isTornOff` windows.
- `activeApplicationChanged(_:)` or its helper orders torn-off windows out for non-target apps and fronts them only for their target app.
- Main and nested submenu parents both capture detached source row and item identity before clearing `childSubmenuRow`.
- Detached matching uses AX identity when possible with safe fallback attributes, not row-only matching.
- User-closed detached references are ignored/pruned.
- Mouse-up detached-copy policy runs before the existing `pressedOpenSubmenuRow` branch in nested submenus and clears hover/highlight state.

Manual verification:

1. Tear off a submenu; open the main NeXTMenus menu and confirm the main/attached menu appears above the torn-off menu.
2. Confirm the torn-off menu still floats above ordinary target app windows.
3. Switch to another app and confirm torn-off menus for the previous target app disappear.
4. Switch back to the target app and confirm the torn-off menu reappears at its previous position.
5. Close a torn-off menu with its close button; switch away/back and confirm it does not resurrect.
6. Tear off a main-menu child submenu, then click the same main-menu row:
   - any temporary attached copy hides on mouse-up;
   - the torn-off copy remains.
7. Repeat the same already-torn-off click behavior for a nested submenu row.
8. Confirm the recent behavior remains intact:
   - attached already-open submenu row click no-ops;
   - torn-off already-open submenu row click closes child on mouse-up and clears highlight.

Verification commands:

```bash
git diff --check
make check-sources
swift test
swift build
make verify
```

## Worktree strategy

After design/plan approval and a clean main worktree, create a dedicated worktree:

- Branch: `fix/torn-off-menu-behavior`
- Worktree: `.worktrees/fix/torn-off-menu-behavior/`

Before implementation:

1. Inspect dirty state with `git status --short --branch`.
2. Commit or otherwise resolve this plan document before creating the implementation worktree.
3. Confirm `.worktrees/` is ignored with `git check-ignore .worktrees/`.
4. Confirm existing worktrees with `git worktree list`.
5. Create the worktree with `git worktree add -b fix/torn-off-menu-behavior .worktrees/fix/torn-off-menu-behavior main`.
6. Run baseline `swift test` in the worktree.

## Risks and mitigations

- **Window-level ambiguity:** `.floating` should be validated manually. If it is too low, use a custom level below `.popUpMenu` but above ordinary app windows.
- **Order-front side effects:** `orderFrontRegardless()` can raise torn-off windows within their level; keeping level below `.popUpMenu` should preserve main-menu priority.
- **Detached identity staleness:** parent rows can change when modifier-filtered menu items change. Mitigate by storing source row plus menu item identity, preferring `CFEqual` AX-element comparison and falling back to title/shortcut/kind attributes.
- **Accidentally closing the torn-off copy:** only call `hideWindow()`/`closeSubmenu()` on the current attached child, not on retained detached references.
- **Nested chain behavior:** apply the same logic in both `MenuWindowController` and `SubmenuWindowController`, and manually verify nested submenu rows.
- **Active app edge cases:** fullscreen spaces and `.canJoinAllSpaces` can affect visibility; manual verification is required.

## Review gate

Before implementation approval, review this plan for:

- z-order target level choice;
- active-app visibility lifecycle;
- detached row tracking strategy;
- automated/manual test coverage;
- worktree and verification steps.
