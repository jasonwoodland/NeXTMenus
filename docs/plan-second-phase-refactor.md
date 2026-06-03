# Second-Phase Refactor Plan

## Status

Phase 1 is implemented and merged to `main` as `4b11d3d refactor: extract main menu row mapping`.

Phase 2 design is approved for planning: extract tested per-row highlight appearance predicates only. The refactor remains explicitly scoped as behavior-preserving; UX changes should be captured as separate follow-ups.

## Context

NeXTMenus now has a healthier package/build shape after the first cleanup:

- App source: `Sources/NeXTMenus/`
- Testable model/visibility code: `Sources/NeXTMenusKit/`
- Tests: `Tests/NeXTMenusKitTests/`
- Build/release verification: `make verify`

The remaining complexity is concentrated in two stateful AppKit controllers:

- `Sources/NeXTMenus/MenuWindowController.swift` — ~1434 lines
- `Sources/NeXTMenus/SubmenuWindowController.swift` — ~1882 lines

Their behavior has been refined through many iterations, so the second phase should first preserve and characterize behavior, then extract pure/stateful pieces in small, reversible steps.

## Goals

1. Drastically simplify `MenuWindowController` and `SubmenuWindowController` without regressing menu behavior.
2. Move pure row mapping, visibility, highlight, and interaction decisions into `NeXTMenusKit` where they can be tested.
3. Keep AppKit/AX/window code in thin controller layers.
4. Make future fixes easier by replacing implicit row-index state and duplicated branches with named models and policies.
5. Add characterization tests before each behavior-moving refactor.

## Non-goals

- No intentional UX changes unless separately approved.
- No rewrite of the app architecture in one large step.
- No replacement of AppKit windows, Accessibility APIs, or the existing build system.
- No broad style-only cleanup unless it directly supports a behavior-preserving extraction.

## Design decision

Phase 2 is strict behavior-preserving only. If simplification reveals a desirable UX change, record it as a separate follow-up instead of mixing it into this refactor.

## High-level strategy

Use a strangler-style refactor:

1. Add pure tests around current behavior.
2. Extract one small pure model or policy.
3. Replace controller code with calls to that model.
4. Run `make verify` and focused manual checks.
5. Repeat.

Avoid large simultaneous moves across row mapping, rendering, submenu lifecycle, and event handling.

## Phase 1: Extract pure main-menu row mapping

### Files

- Add: `Sources/NeXTMenusKit/MenuRow.swift`
- Add: `Sources/NeXTMenusKit/MainMenuRows.swift`
- Add tests in `Tests/NeXTMenusKitTests/MainMenuRowsTests.swift`
- Modify: `Sources/NeXTMenus/MenuWindowController.swift`

### Current logic to move or preserve

Move only pure row indexing and selectability decisions from `MenuWindowController.swift`:

- `TrailingAction` as a pure `MainMenuTrailingAction` type, or equivalent.
- `visibleTrailingActions` as a pure function of explicit inputs: `showHide`, `showQuit`, and `isFinderTarget`.
- `firstPromotedAppMenuItemRow` / `firstTrailingActionRow` index calculations.
- `promotedAppMenuItem(at:)` row lookup against already-computed promoted items.
- `mainMenuItem(at:)` row lookup against already-computed visible/promoted items.
- `trailingAction(at:)` row lookup against already-computed trailing actions.
- row count logic in `numberOfRows(in:)`.
- selectability logic in `tableView(_:shouldSelectRow:)`.

Keep App-only dependencies in `MenuWindowController`:

- `NeXTMenusSettings` remains in the app target; the controller reads settings and passes booleans into the pure row model.
- `MenuExtractor.submenuItems(for:)` remains in the app target; the controller computes/caches `promotedAppMenuItems` and passes that array into the pure row model.
- `promotedAppMenuItemsCache` and `menuItemsVersion` invalidation remain in the controller during Phase 1.
- AX-backed `MenuItem.element` values remain opaque; Phase 1 must not compare `MenuItem` values for equality.

### Target shape

Introduce a pure row model that uses explicit input arrays/config and exposes Equatable row kinds/projections rather than requiring `MenuItem: Equatable`.

Example shape:

```swift
public enum MainMenuTrailingAction: Equatable {
    case hide
    case quit
    case logOut
}

public enum MainMenuRowKind: Equatable {
    case appInfo
    case menuItem(index: Int)
    case promotedAppMenuItem(index: Int)
    case trailingAction(MainMenuTrailingAction)
}

public struct MainMenuRows {
    public let appMenuItem: MenuItem?
    public let visibleMenuItems: [MenuItem]
    public let promotedAppMenuItems: [MenuItem]
    public let trailingActions: [MainMenuTrailingAction]

    public var count: Int { ... }
    public func kind(at row: Int) -> MainMenuRowKind?
    public func menuItem(at row: Int) -> MenuItem?
    public func trailingAction(at row: Int) -> MainMenuTrailingAction?
    public func isSelectable(row: Int) -> Bool
}
```

Tests should assert `MainMenuRowKind` and lightweight projections such as title/enabled/separator rather than raw `MenuItem` equality.

`MenuWindowController` remains responsible for side-effectful/config inputs:

1. Build `visibleMenuItems` with existing `MenuItemVisibility.visibleItems(... trimSeparators: false)`.
2. Build/cached `promotedAppMenuItems` exactly as today.
3. Build `trailingActions` from `NeXTMenusSettings` and Finder detection.
4. Ask `MainMenuRows` for row kind, item lookup, trailing action lookup, count, and selectability.

### Behavior preservation details

- Info row always exists and remains row `0`.
- Info row selectability remains `appMenuItem?.isEnabled ?? true`, including nil and disabled app-menu cases.
- Main menu rows continue to use `trimSeparators: false`.
- Services promotion remains exactly `!item.isSeparator && item.title == "Services"` from `MenuExtractor.submenuItems(for: appMenuItem)`.
- Promoted Services row ordering remains after visible main menu rows and before trailing actions.
- `promotedAppMenuItemsCache` remains versioned by `menuItemsVersion` and is still cleared by `invalidateVisibleMenuItemsCache()`.
- Hide/Quit/Log Out row ordering and shortcuts remain unchanged.
- Finder continues to show Log Out instead of Quit when `targetApp?.bundleIdentifier == "com.apple.finder"`.
- Phase 1 must not change initial window sizing/resizing behavior. In particular, do not replace the current initializer height calculation (`menuItems.count + 1 + trailing`) with extracted row count unless that behavior is separately characterized and approved.

### Tests

Cover:

- Info row always exists.
- Nil app menu defaults to selectable Info row.
- Disabled app menu makes Info row unselectable.
- Main menu rows follow visible menu item order.
- Main menu intentionally uses `trimSeparators: false` in the controller-facing setup.
- Services promotion includes only non-separator item titled `"Services"`.
- Promoted rows appear after visible main rows and before trailing actions.
- No promoted rows appear when `showServicesInMainMenu` input is false or no Services item is provided.
- Hide row appears only when configured.
- Quit row appears only when configured and target is not Finder.
- Finder uses Log Out instead of Quit when Quit row is configured.
- Disabled/separator menu rows are not selectable.
- Settings combinations for hide/quit produce the expected trailing action list.

### Verification

- `swift test`
- `make verify`
- Manual: top-level menu still shows Info, Services, Hide/Quit/Log Out correctly.
- Manual: initial menu height and subsequent resize behavior appear unchanged.

## Phase 2: Extract highlight appearance policy

### Approved scope

Phase 2 is behavior-preserving and limited to per-row highlight/render-state predicates. It must not move event mutation, submenu lifecycle, timers, AppKit view mutation, AX calls, torn-off/window behavior, or reducer-style interaction handling.

Controllers remain responsible for:

- mouse event handlers and row tracking state mutation;
- opening, closing, and retaining submenu controllers;
- computing controller-local row facts such as selectability, trailing-action status, and submenu-row status;
- AppKit view lookup and mutation in `updateRowHighlight(forRow:)`;
- flash timers and action execution.

`NeXTMenusKit` should only answer: given the current row facts and interaction state snapshot, what highlight appearance should this row have?

### Files

- Add: `Sources/NeXTMenusKit/MenuHighlightPolicy.swift`
- Add tests in `Tests/NeXTMenusKitTests/MenuHighlightPolicyTests.swift`
- Modify:
  - `NeXTMenus.xcodeproj/project.pbxproj`
  - `Sources/NeXTMenus/MenuWindowController.swift`
  - `Sources/NeXTMenus/SubmenuWindowController.swift`

Do not add `MenuInteractionState.swift` in Phase 2 unless implementation evidence shows a tiny shared value type is needed. Broader interaction-state reducers belong to Phase 3.

### Target API shape

Use one shared policy type with separate main/submenu entry points so the two controllers' subtle behavior differences stay explicit:

```swift
public struct MenuRowAppearance: Equatable {
    public let isHighlighted: Bool
    public let isEmphasized: Bool
}

public struct MenuRowFlash: Equatable {
    public let row: Int
    public let isOn: Bool
}

public enum MenuHighlightPolicy {
    public static func mainRowAppearance(
        row: Int,
        isHoverable: Bool,
        isTrailingAction: Bool,
        hoveredRow: Int?,
        childSubmenuRow: Int?,
        childHasMouse: Bool,
        pressedRow: Int?,
        isDragging: Bool,
        isMenuActive: Bool,
        flash: MenuRowFlash?
    ) -> MenuRowAppearance

    public static func submenuRowAppearance(
        row: Int,
        isHoverable: Bool,
        isSubmenuRow: Bool,
        hoveredRow: Int?,
        childSubmenuRow: Int?,
        childHasMouse: Bool,
        isDragging: Bool,
        isTornOff: Bool,
        flash: MenuRowFlash?
    ) -> MenuRowAppearance
}
```

`MenuRowAppearance.isHighlighted` drives the background hidden state, `NSTableCellView.backgroundStyle`, and `ShortcutView.setEmphasized(_:)`. `MenuRowAppearance.isEmphasized` drives the selection background `NSVisualEffectView.isEmphasized` value. Keep those two outputs separate because the current code computes visual-effect emphasis independently from whether the highlight background is hidden.

### Current logic to extract

Extract the boolean decision logic from:

- `MenuWindowController.updateRowHighlight(forRow:)`
- `SubmenuWindowController.updateRowHighlight(forRow:)`

Keep the controller-side mechanics around the extracted call:

1. Look up the cell view and background/shortcut subviews.
2. Compute row facts using existing helpers:
   - main `isHoverable`: current `tableView(_:shouldSelectRow:)` / `mainMenuRows.isSelectable(row:)` result;
   - main `isTrailingAction`: `trailingAction(at: row) != nil`;
   - submenu `isHoverable`: current `tableView(_:shouldSelectRow:)` result;
   - submenu `isSubmenuRow`: existing enabled, non-separator, has-submenu predicate.
3. Convert controller flash tuples to `MenuRowFlash(row:isOn:)`.
4. Ask `MenuHighlightPolicy` for `MenuRowAppearance`.
5. Apply returned values to AppKit views exactly where the controller currently mutates them.

### Behavior preservation details

Main menu policy must preserve:

- Flash state overrides normal highlight selection for the flashing row, including flash-off producing an unhighlighted row.
- A plain hover over a main row with no open submenu/tracking state remains unhighlighted.
- A child submenu row stays highlighted while its submenu is open.
- When a child submenu is open, hovering a sibling main row highlights that sibling.
- During click-drag over main rows, only the hovered row highlights.
- During click-drag off main rows, the open child row remains highlighted.
- Main trailing actions do not highlight on plain hover.
- Main trailing actions highlight when pressed or when the main menu is in click-open tracking mode.
- The open-submenu row de-emphasizes when `childHasMouse` is true or when dragging with the pointer off main rows.
- Disabled/separator/non-hoverable rows do not highlight except through the existing flash override.

Submenu policy must preserve:

- Flash state overrides normal highlight selection for the flashing row, including flash-off producing an unhighlighted row.
- Attached submenus highlight any hoverable hovered row.
- Attached submenus keep the open child submenu row highlighted.
- Torn-off submenus keep the open child submenu row highlighted.
- Torn-off submenu leaf rows do not highlight on plain hover.
- Torn-off submenu rows highlight on hover while click-dragging.
- Torn-off submenu rows that themselves have submenus highlight on hover while another child submenu is open.
- The open child submenu row de-emphasizes when `childHasMouse` is true.
- Disabled/separator/non-hoverable rows do not highlight except through the existing flash override.

### Tests

Add characterization tests before replacing the controller logic. Cover at least:

- Main plain hover with no child submenu remains unhighlighted.
- Main row with child submenu open is highlighted.
- Main sibling hover while child submenu is open is highlighted.
- Main drag over a row highlights only that row.
- Main open child row is highlighted but de-emphasized when `childHasMouse == true`.
- Main drag off rows keeps the open child row highlighted and de-emphasized.
- Main trailing action plain hover is unhighlighted.
- Main trailing action pressed is highlighted.
- Main trailing action in tracking mode is highlighted.
- Main flash on/off overrides normal row state.
- Main non-hoverable row stays unhighlighted without flash.
- Submenu attached hover is highlighted.
- Submenu attached child row is highlighted.
- Submenu torn-off leaf hover is unhighlighted.
- Submenu torn-off drag hover is highlighted.
- Submenu torn-off submenu row while child open is highlighted.
- Submenu child pointer de-emphasis is represented.
- Submenu flash on/off overrides normal row state.
- Submenu non-hoverable row stays unhighlighted without flash.

### Implementation order

1. Create a fresh Phase 2 worktree from `main` after implementation approval:
   - Branch: `refactor/menu-highlight-policy`
   - Worktree: `.worktrees/refactor/menu-highlight-policy/`
2. Run baseline verification in that worktree.
3. Add failing `MenuHighlightPolicyTests` for the characterization matrix.
4. Add `MenuHighlightPolicy.swift` in `NeXTMenusKit` and update the Xcode source list.
5. Replace the duplicated boolean logic inside both controllers' `updateRowHighlight(forRow:)` methods with policy calls.
6. Run focused tests, source-list check, `git diff --check`, and `make verify`.
7. Perform implementation review before commit/handoff.

### Verification

- `swift test`
- `make check-sources`
- `git diff --check`
- `make verify`
- Manual hover/press behavior in main and submenu windows:
  - main plain hover before opening any submenu;
  - click-open main row and hover siblings;
  - click/press Hide or Quit/Log Out row;
  - drag from main row into child submenu;
  - attached submenu hover and child hover;
  - torn-off submenu leaf hover and submenu-row hover.

## Phase 3: Extract interaction reducer after highlight policy is covered

### Files

- Add or extend: `Sources/NeXTMenusKit/MenuInteractionState.swift`
- Add tests in `Tests/NeXTMenusKitTests/MenuInteractionStateTests.swift`
- Modify:
  - `Sources/NeXTMenus/MenuWindowController.swift`
  - `Sources/NeXTMenus/SubmenuWindowController.swift`

### Current logic to simplify

Move decisions, not side effects, from:

`MenuWindowController.swift`:

- `handleMouseMoved(_:)`
- `handleMouseExited()`
- `handleMouseDown(_:)`
- `handleMouseDragged(_:)`
- `handleMouseUp(_:wasDragged:)`
- `updateOpenSubmenu(forHoveredRow:)`
- `collapseSubmenus(endsTracking:)`
- `resetInteractionStateForVisibleItemsChange()`

`SubmenuWindowController.swift`:

- `handleMouseMoved(_:)`
- `handleMouseExited()`
- `handleMouseDown(_:)`
- `handleMouseDragged(_:)`
- `handleMouseUp(_:wasDragged:)`
- `handleMouseClickedRow(_:)`
- `updateOpenSubmenu(forHoveredRow:)`
- `closeSubmenu()`
- `resetInteractionStateForVisibleItemsChange()`

### Target shape

Controllers still own AppKit and AX side effects. A pure reducer returns intents such as:

- update highlight
- open submenu for row
- close submenu
- perform action for row
- enter/exit tracking mode
- reset interaction state
- consume event

### Verification

- `swift test`
- `make verify`
- Manual interaction trace matrix:
  - plain hover does not open main submenus until tracking is active
  - click opens submenu
  - click same open row toggles closed on mouse-up
  - click-drag switches submenus
  - drag into child and release triggers child row
  - modifier changes close stale submenu state

## Phase 4: Remove duplicated legacy submenu selection path

### File

- Modify: `Sources/NeXTMenus/SubmenuWindowController.swift`

### Current concern

`tableViewSelectionDidChange(_:)` duplicates submenu/action logic and can bypass the standard child-controller wiring used by `makeChildController`, callbacks, and action paths.

### Plan

1. First determine whether this delegate path is still reachable after `HoverTableView` mouse handling.
2. If reachable, route it into the existing characterized handler (`handleMouseClickedRow` or equivalent reducer intent).
3. If unreachable, remove delegate assignment or leave a defensive deselect-only path with a comment.

### Verification

- `swift test`
- `make verify`
- Manual: keyboard/table selection or accidental selection does not create a child submenu without callbacks.

## Phase 5: Extract child submenu coordination

### Files

- Add: `Sources/NeXTMenus/SubmenuCoordinator.swift` or `Sources/NeXTMenus/MenuChainCoordinator.swift`
- Modify:
  - `Sources/NeXTMenus/MenuWindowController.swift`
  - `Sources/NeXTMenus/SubmenuWindowController.swift`

### Current duplicated concepts

- `makeChildController(...)`
- `presentSubmenu(...)` / `showSubmenu(...)`
- `closeSubmenu()` / `collapseSubmenus(...)`
- `raiseSubmenuChain()` / `bringChainToFront()`
- `containsScreenPointInChain(_:)`
- `onWillHide`
- `onTornOff`
- `dismissChain`
- `onPointerEntered`
- detached submenu retention

### Plan

Extract shared chain behavior while injecting policy differences:

- main menu vs submenu root behavior
- attached vs torn-off dismissal behavior
- action dismissal behavior
- child pointer de-emphasis behavior

### Verification

- `make verify`
- Manual:
  - nested submenu chain opens and raises correctly
  - torn-off submenu stays alive
  - closing child clears parent highlight
  - action deep in attached chain dismisses correctly
  - action in torn-off chain does not dismiss the torn-off ancestor

## Phase 6: Extract action performer and flash behavior

### Files

- Add: `Sources/NeXTMenus/MenuActionPerformer.swift`
- Modify:
  - `Sources/NeXTMenus/MenuWindowController.swift`
  - `Sources/NeXTMenus/SubmenuWindowController.swift`

### Current logic

- `flashRow(_:completion:)` duplicated across both controllers.
- AX action execution repeats target activation, `usleep(50000)`, and `AXUIElementPerformAction`.
- Main trailing actions handle Hide/Quit/Log Out separately.
- Torn-off submenu actions perform immediately and stay open, with optimistic checkmark refresh.

### Plan

Extract a side-effect wrapper with explicit policies:

- attached leaf action: flash -> activate target -> delay -> AX press -> dismiss chain
- torn-off leaf action: AX press immediately -> optimistic mark refresh -> stay open
- main trailing action: flash -> Hide/Quit/Log Out

### Verification

- `make verify`
- Manual:
  - leaf action still flashes and executes
  - torn-off checked item updates mark
  - Hide/Quit rows flash then execute
  - Finder Log Out row still sends the intended Apple event

## Phase 7: Extract view/cell rendering

### Files

- Add: `Sources/NeXTMenus/MenuCellRenderer.swift`
- Possibly add: `Sources/NeXTMenus/MenuTableBuilder.swift`
- Modify:
  - `Sources/NeXTMenus/MenuWindowController.swift`
  - `Sources/NeXTMenus/SubmenuWindowController.swift`

### Current logic

Both controllers construct similar cells with:

- highlight background
- title text
- chevron
- shortcut rendering
- separator handling
- emphasized shortcut state

Submenus additionally have:

- mark/check glyph
- dynamic width
- shorter separator rows

### Plan

1. Extract shared identifiers and view lookup helpers.
2. Extract main-cell configuration and submenu-cell configuration as separate functions using common primitives.
3. Avoid changing layout constants until after visual verification.

### Verification

- `make verify`
- Manual visual checks in light/dark mode:
  - disabled text
  - separator lines
  - shortcut alignment
  - chevrons
  - checkmarks/diamonds
  - highlight shape/material

## Phase 8: Isolate scrolling and torn-off subsystems last

### Submenu scrolling

Candidate file: `Sources/NeXTMenus/SubmenuScrollingController.swift`

Move:

- `SubmenuScrollCaretView`
- `ScrollDirection`
- `setScrolling(_:active:)`
- `scrollByRows(_:)`
- `handleScrollWheel(_:)`
- `updateHoverAfterScroll()`
- `updateRowVisibilityForScrollCarets()`
- `clearHoverForScrollCaretIfNeeded()`
- `layoutScrollCaretViews(canScrollUp:canScrollDown:)`
- `updateScrollCaretVisibility()`
- constrained-height helpers only if dependencies stay manageable

### Torn-off state

Candidate file: `Sources/NeXTMenus/TornOffSubmenuState.swift`

Move or isolate:

- movement threshold logic
- `isTornOff`
- `userClosed`
- app switch visibility
- close-button behavior
- child retention after tear-off

### Verification

- `make verify`
- Manual:
  - long submenu scrolls with carets
  - wheel scroll snaps correctly
  - rows under carets fade/hide correctly
  - hover over carets does not trigger row selection
  - dragging submenu more than threshold tears it off
  - torn-off submenu persists across parent closure
  - torn-off submenu hides/shows with target app frontmost state

## Manual regression matrix

Run after any phase that touches interaction code:

1. Launch app and grant/access Accessibility if needed.
2. Main menu:
   - plain hover over top-level rows
   - click top-level row to open submenu
   - hover sibling while submenu open
   - click same open row to close
   - press Hide and Quit rows
   - Finder target shows Log Out instead of Quit
3. Submenus:
   - click leaf item
   - click submenu item
   - click-drag into child and release
   - drag between sibling submenu rows
   - click outside to dismiss
4. Modifiers:
   - hold Option/Shift/Control while menus are open
   - confirm alternate rows update and stale submenu state closes
5. Torn-off menus:
   - drag submenu to tear off
   - interact with leaf rows
   - open child from torn-off submenu
   - close torn-off submenu with close button
   - switch away and back to target app
6. Long submenus:
   - scroll wheel
   - hover top/bottom carets
   - confirm constrained height and positioning
7. Screens/window movement:
   - move target app between displays
   - move menu window across screens
   - verify positioning and visible bounds

## Verification commands

Run at every checkpoint:

```bash
make check-sources
swift test
swift build
make release
```

Or simply:

```bash
make verify
```

Before final handoff:

```bash
git diff --check
make verify
```

## Branch/worktree strategy for implementation

Create a dedicated worktree per approved phase from the canonical repo-local path. The branch name and worktree path must match one-to-one.

For the approved Phase 2 implementation slice, use:

- Branch: `refactor/menu-highlight-policy`
- Worktree: `.worktrees/refactor/menu-highlight-policy/`

Before creating any phase worktree:

1. Inspect dirty state with `git status --short --branch`.
2. If the repo is not clean, stop and resolve, commit, stash, or explicitly confirm how to carry the changes before creating the phase worktree from `main`.
3. Confirm whether the repo is already in a linked worktree with `git rev-parse --show-toplevel` and `git worktree list`.
4. Confirm `.worktrees/` is ignored with `git check-ignore .worktrees/`.
5. If `.worktrees/` is not ignored, add or choose an approved alternative before creating the worktree.
6. Do not reuse a prior phase worktree for a new branch.

## Review gates

Each phase should have:

1. Focused tests or manual characterization notes before code movement.
2. Implementation in one small commit-sized change.
3. `make verify` pass.
4. Code review before proceeding to the next phase.

## Recommended next implementation slice

Phase 1 is complete and merged. The next approval should cover Phase 2 only.

Start with:

- Add `MenuHighlightPolicy` and characterization tests.
- Replace only the highlight predicate logic inside the two `updateRowHighlight(forRow:)` methods.
- Do not touch event handling, submenu coordination, action execution, rendering layout, scrolling, or torn-off behavior beyond applying the returned highlight appearance.

This keeps Phase 2 small, testable, and behavior-preserving. Later phases still require separate review/approval after Phase 2 is verified.
