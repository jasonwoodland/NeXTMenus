# Phase 3H Row Action Execution Intent Plan

## Status

Planning draft. Phase 3H is the next narrow behavior-preserving refactor after Phase 3G and the nested submenu tear-off fix.

Recently completed and pushed:

- `a7f5527 docs: add phase 3g submenu click intent plan`
- `8c23384 fix: preserve nested submenu tear-off`
- `1c3dfd5 refactor: extract submenu click action intent`

Current `main` is clean and synced with `origin/main` at `1c3dfd5`.

## User-reported follow-up issues, out of scope for Phase 3H

The user reported two behavior issues while approving Phase 3H planning:

1. Some apps open with menu items never loading; the menu shows only app/info/hide/quit-style fallback rows, and closing/reopening the app does not fix it until NeXTMenus is restarted.
2. Wireless Diagnostics dynamically changes menu items. In its Window submenu, `Assistant` appears, but expected dynamic entries such as `Info`, `Logs`, `Scan`, and `Performance` are missing. This suggests menu item changes are not reflected in NeXTMenus after extraction/reconfiguration.

These are likely AX extraction/cache/reload/dynamic menu mutation issues. They are important, but they are **not** part of Phase 3H because this phase only extracts a pure decision over already-computed row facts. Phase 3H should not change menu extraction, refresh timing, caching, app observation, reconfiguration, or AX menu mutation behavior.

Recommended follow-up after Phase 3H: a separate investigation/fix plan for dynamic menu refresh/reload behavior.

## Context

Phase 3H targets only two controller methods:

- `Sources/NeXTMenus/MenuWindowController.swift`
  - `executeActionAtRow(_:)`
- `Sources/NeXTMenus/SubmenuWindowController.swift`
  - `executeActionAtRow(_:)`

Current behavior:

### Main menu `executeActionAtRow(_:)`

Current main behavior:

1. Return if `row < 0`.
2. Ask the table delegate whether the row is selectable.
3. Get `mainMenuItem(at: row)`.
4. Return if there is no menu item or no AX element.
5. Activate the target app.
6. Sleep briefly with `usleep(50000)`.
7. Perform `kAXPressAction` on the element.
8. Call `dismissAfterAction()`.

Important current semantics:

- High out-of-bounds rows are safe today because main row helpers/delegate paths tolerate missing projected rows.
- Selectable trailing action rows such as Hide/Quit are ignored by this method because `mainMenuItem(at:)` returns nil for those rows.
- This method does not check whether the item is a leaf or submenu-capable; if a selectable row has a menu item element, it can perform.
- Main dismisses after action.

### Submenu `executeActionAtRow(_:)`

Current submenu behavior:

1. Return if `row` is outside `0..<visibleMenuItems.count`.
2. Ask the table delegate whether the row is selectable.
3. Read `visibleMenuItems[row]`.
4. Return if there is no AX element.
5. Activate the target app.
6. Sleep briefly with `usleep(50000)`.
7. Perform `kAXPressAction` on the element.

Important current semantics:

- Bounds must be checked before delegate selectability because the submenu delegate indexes `visibleMenuItems[row]`.
- This method does not call `dismissChain`, `dismissAfterAction`, `performAction(_:at:)`, flash rows, refresh torn-off menus, or update checkmark state.
- This method does not check whether the item is a leaf or submenu-capable; if a selectable row has an element, it can perform.
- Submenu does **not** dismiss after action in this parent-called path.

## Goals

1. Preserve current behavior exactly.
2. Extract only the pure row action execution decision into `NeXTMenusKit`.
3. Keep row/item lookup, delegate selectability, AX elements, app activation, sleeps, AX actions, and dismissal side effects in controllers.
4. Preserve main/submenu asymmetries, especially main-only dismissal.
5. Add focused tests in `MenuInteractionStateTests` for the pure decision.
6. Keep the slice small and reviewable before investigating dynamic menu refresh bugs.

## Non-goals

- No UX changes.
- No dynamic menu refresh/reload/caching fixes.
- No changes to `MenuExtractor`, app observation, or menu item visibility.
- No changes to `performAction(_:at:)`, trailing actions, submenu clicked-row behavior, mouse-up behavior, or torn-off refresh behavior.
- No movement of AX/AppKit/window/action/timer side effects into `NeXTMenusKit`.
- No new leaf-only gating; submenu-capable rows with AX elements must continue to be eligible.
- No unification that hides main/submenu bounds and dismissal asymmetries.

## Proposed API

Add a pure intent type to `Sources/NeXTMenusKit/MenuInteractionState.swift`:

```swift
public enum RowActionExecutionIntent: Equatable {
    case ignore
    case perform(row: Int, dismissAfterAction: Bool)
}
```

Add explicit policy functions:

```swift
public static func mainRowActionExecutionIntent(
    row: Int,
    isInBounds: Bool,
    isSelectable: Bool,
    hasMenuItem: Bool,
    hasElement: Bool
) -> RowActionExecutionIntent

public static func submenuRowActionExecutionIntent(
    row: Int,
    isInBounds: Bool,
    isSelectable: Bool,
    hasElement: Bool
) -> RowActionExecutionIntent
```

Expected behavior:

- Main returns `.perform(row: row, dismissAfterAction: true)` only when:
  - `row >= 0`
  - `isInBounds == true`
  - `isSelectable == true`
  - `hasMenuItem == true`
  - `hasElement == true`
- Submenu returns `.perform(row: row, dismissAfterAction: false)` only when:
  - `row >= 0`
  - `isInBounds == true`
  - `isSelectable == true`
  - `hasElement == true`
- All other combinations return `.ignore`.

The helper is pure. It must not read menu items, call AppKit, inspect AX elements, activate apps, sleep, perform actions, dismiss, update windows, or mutate controller state.

## Controller application shape

### Main

`MenuWindowController.executeActionAtRow(_:)` should:

1. Compute `isInBounds = row >= 0 && row < mainMenuRows.count`.
2. Preserve current safe delegate selectability cadence.
3. Capture `menuItem` and `element` in the controller.
4. Ask `MenuInteractionPolicy.mainRowActionExecutionIntent(...)`.
5. On `.ignore`, return.
6. On `.perform(_, let dismissAfterAction)`, use the captured element to:
   - `targetApp?.activate(options: [])`
   - `usleep(50000)`
   - `AXUIElementPerformAction(element, kAXPressAction as CFString)`
   - call `dismissAfterAction()` only if the intent says so.

Guardrails:

- Do not make trailing Hide/Quit rows perform through this method; `hasMenuItem == false` should keep them ignored here.
- Do not re-index from the returned row when performing; use the captured `AXUIElement`.

### Submenu

`SubmenuWindowController.executeActionAtRow(_:)` should:

1. Compute `isInBounds = row >= 0 && row < visibleMenuItems.count` before delegate or item lookup.
2. Compute selectability only if `isInBounds` is true.
3. Capture `menuItem` and `element` in the controller.
4. Ask `MenuInteractionPolicy.submenuRowActionExecutionIntent(...)`.
5. On `.ignore`, return.
6. On `.perform(_, let dismissAfterAction)`, use the captured element to:
   - `targetApp?.activate(options: [])`
   - `usleep(50000)`
   - `AXUIElementPerformAction(element, kAXPressAction as CFString)`
   - not dismiss, because submenu intent returns `dismissAfterAction: false`.

Guardrails:

- Do not call the submenu delegate for out-of-bounds rows.
- Do not introduce leaf-only or `hasSubmenu == false` semantics.
- Do not call `performAction(_:at:)`, flash rows, refresh torn-off menus, or dismiss chains in this path.

## Files

Modify:

- `Sources/NeXTMenusKit/MenuInteractionState.swift`
- `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift`
- `Sources/NeXTMenus/MenuWindowController.swift`
- `Sources/NeXTMenus/SubmenuWindowController.swift`

No project-file update is expected.

## Test plan

Add focused pure tests in `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift` before implementation.

Main row action execution tests:

- Negative row returns `.ignore`.
- High out-of-bounds row returns `.ignore`.
- Nonselectable row returns `.ignore`.
- Missing menu item returns `.ignore`, even if selectable and element-like facts are true.
- Missing element returns `.ignore`.
- Valid selectable row with menu item and element returns `.perform(row:, dismissAfterAction: true)`.
- Conflict precedence: invalid bounds/selectability facts win even when element facts are true.

Submenu row action execution tests:

- Negative row returns `.ignore`.
- High out-of-bounds row returns `.ignore`.
- Nonselectable row returns `.ignore`.
- Missing element returns `.ignore`.
- Valid selectable row with an element returns `.perform(row:, dismissAfterAction: false)`.
- A submenu-capable row with an element still performs, modeled by the absence of any `hasSubmenu` input/gating.
- Conflict precedence: invalid bounds/selectability facts win even when element facts are true.

Existing tests for outside-click, clicked-row, hover, mouse-down/up, reset, drag-hover, and highlight behavior should remain green.

## Implementation steps

1. Keep this plan on clean `main` and review it before implementation.
2. Commit the reviewed plan on `main` after user approval, if the only change is this doc.
3. Create a dedicated worktree/branch:
   - Branch: `refactor/row-action-execution-intent`
   - Worktree: `.worktrees/refactor/row-action-execution-intent/`
4. Run baseline tests in the worktree:
   - `swift test`
5. Add failing `MenuInteractionStateTests` for row action execution intent.
6. Run focused tests and confirm expected RED:
   - `swift test --filter MenuInteractionStateTests`
7. Implement `RowActionExecutionIntent` and the two policy functions.
8. Refactor both controller methods while preserving controller-owned side effects and fact-gathering guardrails.
9. Run focused tests to GREEN.
10. Run full verification:
    - `git diff --check`
    - `make check-sources`
    - `swift test`
    - `swift build`
    - `make verify`
11. Request implementation review.
12. Commit the implementation branch after review passes.
13. Manual smoke before merge.

## Manual verification matrix

- Main menu parent-called action execution still activates the app, performs the AX press, and dismisses NeXTMenus.
- Main trailing Hide/Quit rows still do not execute through `executeActionAtRow(_:)`.
- Submenu parent-called action execution still activates the app and performs AX press without calling the submenu `performAction` flash/refresh path.
- Submenu execution still does not dismiss the chain through this path.
- Existing Phase 3G clicked-row behavior still works.
- Nested submenu tear-off fix remains intact.

## Risks and mitigations

- **Bounds/indexing drift:** keep main and submenu fact-gathering separate; submenu must bounds-check before delegate or item lookup.
- **Dismissal drift:** encode `dismissAfterAction` in the intent output and test main true/submenu false.
- **Leaf-only drift:** do not include `hasSubmenu` in the API; current code performs based on element presence, not leaf status.
- **Trailing-action drift:** main requires `hasMenuItem` so selectable trailing rows still ignore in this path.
- **Side-effect movement:** keep AX/AppKit/sleep/dismiss work in controllers.
- **Re-indexing drift:** controllers should use captured `AXUIElement`, not re-read rows after intent.
- **Dynamic refresh temptation:** do not change extraction/reload/cache behavior in this phase.

## Approval gate

Implementation should not start until:

1. This plan is reviewed.
2. Material review concerns are addressed.
3. The user approves committing the plan, creating the worktree/branch, and implementing Phase 3H.
