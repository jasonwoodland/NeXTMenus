# Plan: Non-Forced Wireless Diagnostics Window Submenu Items

## Objective

Fix the missing Wireless Diagnostics `Window` submenu rows without opening or refreshing native macOS menus. The intended approach is to synthesize Window-menu-like entries from the target app's existing Accessibility windows (`AXWindows`) and execute those synthesized rows by raising the corresponding AX window.

## Background and Research Evidence

The prior forced-refresh experiment was rejected by smoke testing because it briefly opened native macOS menus, delayed NeXTMenus submenu opening, and still did not reveal the Wireless Diagnostics dynamic `Window` items. This plan explicitly avoids that approach.

Current code evidence:

- `MenuExtractor.extractSubmenuItemsOnDemand(from:)` reads `AXChildren` and only presses when children are missing/empty. It does not have a non-pressing way to refresh dynamic native menu content.
  - `Sources/NeXTMenus/MenuExtractor.swift`
- `MenuExtractor.extractSubmenuItems(from:)` only extracts `AXMenu` and `AXMenuItem` children; it has no fallback that can synthesize rows from app windows.
  - `Sources/NeXTMenus/MenuExtractor.swift`
- `MenuItem` currently stores a single `element: AXUIElement?`, and action execution paths assume the element should be invoked with `kAXPressAction`.
  - `Sources/NeXTMenusKit/MenuItem.swift`
  - `Sources/NeXTMenus/MenuWindowController.swift`
  - `Sources/NeXTMenus/SubmenuWindowController.swift`

Non-forced feasible source:

- Enumerate the target app's `kAXWindowsAttribute`.
- Read window titles via `kAXTitleAttribute`.
- Optionally mark the focused/front window by comparing against `kAXFocusedWindowAttribute`.
- Add synthesized rows to the `Window` submenu.
- Invoke synthesized rows with window semantics, likely `kAXRaiseAction`, not `kAXPressAction`.

Important boundary: `AXWindows` can only represent windows that already exist. If `Info`, `Logs`, `Scan`, or `Performance` are hidden commands that create/show windows only when selected from the native menu, this approach cannot recover them without native menu actions or app-specific automation.

## Scope

### In scope

- Add explicit menu item action semantics so NeXTMenus can distinguish normal menu-item press rows from synthesized window-raise rows.
- Synthesize additional `Window` submenu rows from target-app `AXWindows` without opening native menus.
- Avoid duplicates when native menu extraction already includes a window title.
- Keep normal menu item actions, submenu presentation, hover/drag behavior, and torn-off behavior unchanged.
- Keep AppKit/AX side effects in `Sources/NeXTMenus`.
- Put only pure action/merge decisions in `NeXTMenusKit`.

### Out of scope

- Forced native menu opening, `AXPress` refresh, or `AXCancel` refresh loops for dynamic menu population.
- App-specific Wireless Diagnostics automation.
- Creating windows that do not already exist.
- Live updates while a submenu is already open.
- Moving `MenuExtractor` or `NeXTMenusSettings` into `NeXTMenusKit`.

## Branch and Worktree

- Branch: `fix/window-submenu-axwindows`
- Worktree: `.worktrees/fix/window-submenu-axwindows/`

Before creating the worktree, confirm `main` is clean. If not, stop and resolve/confirm first.

## TDD Plan

### 1. Pure action semantics

Add tests in `Tests/NeXTMenusKitTests/MenuItemActionTests.swift` or an existing policy test file.

Expected tests:

- New `MenuItemActionKind.pressMenuItem` is the default action for existing `MenuItem` initializers.
- Synthesized rows can be represented with `MenuItemActionKind.raiseAXWindow`.
- Existing row-action intent tests continue to preserve main/submenu dismissal asymmetry while controllers use the selected row's explicit action kind.

Expected RED: missing action kind/property and any controller dispatcher APIs.

Likely implementation:

- Add a pure enum to `Sources/NeXTMenusKit`, for example:
  - `.pressMenuItem`
  - `.raiseAXWindow`
- Add `actionKind` (or similar) to `MenuItem`, defaulting to `.pressMenuItem` for source compatibility.

### 2. Pure Window submenu merge policy

Add tests in `Tests/NeXTMenusKitTests/WindowSubmenuSynthesisTests.swift`.

Expected tests:

- Non-Window menu titles should not be augmented.
- A `Window` submenu preserves existing native submenu rows.
- A `Window` submenu can be built from synthesized AX-window rows even when native submenu rows are empty.
- Synthesized window rows are appended after existing rows, with a separator only when both sections are nonempty and the existing section does not already end in a separator.
- Duplicate titles are not added when native extraction already includes a matching row.
- Untitled windows are ignored.
- Ordering follows the app's `AXWindows` order.
- Synthesized rows use `.raiseAXWindow` action kind and `hasSubmenu == false`.

Likely implementation:

- Add a pure merge helper to `NeXTMenusKit`, for example `WindowSubmenuSynthesis`, that works from value inputs such as existing `MenuItem`s and synthesized window candidates.
- Keep AX enumeration out of the kit helper.

### 3. App-side AX window enumeration

Add app-side tests only if they can be done with a small seam and without real AX side effects. If SwiftPM executable-target tests become noisy, keep this to code review/manual smoke and rely on pure merge/action tests for unit coverage.

Likely implementation in `Sources/NeXTMenus/MenuExtractor.swift`:

- Add a small app-side helper to read `kAXWindowsAttribute` from `AXUIElementCreateApplication(app.processIdentifier)`.
- For each AX window:
  - read `kAXTitleAttribute`
  - ignore empty titles
  - compare with focused window if available and set `markChar` to `✓` for the active window
  - create a synthesized `MenuItem` with `element` set to the AX window and action kind `.raiseAXWindow`

### 4. Window-submenu augmentation at presentation time

This path must be explicitly non-pressing. It must not call `MenuExtractor.submenuItems(for:)` for `Window` menus, because that helper can fall back to `extractSubmenuItemsOnDemand(from:)`, which may perform `kAXPressAction`/`kAXCancelAction` when native `AXChildren` are empty.

Likely controller/extractor changes:

- Add a Window-specific no-press helper in `Sources/NeXTMenus`, for example `MenuExtractor.submenuItemsWithoutOpeningNativeMenu(for:)`, that reads existing `AXChildren` only and never performs `AXPress` or `AXCancel`.
- In `MenuWindowController.showSubmenu(for:at:)`, if the source item is the `Window` menu and `targetApp` exists, use the no-press helper plus synthesized AX-window rows. If native children are empty, show AXWindows-only rows rather than pressing the native menu.
- Ensure async drag/open paths that can open the `Window` submenu also use the no-press Window-specific path instead of the normal fallback-press path.
- Do the equivalent in `SubmenuWindowController.presentSubmenu(for:at:)` only if nested Window submenus are possible; otherwise keep the change at the main-controller top-level path.
- Do not call `AXPress` or otherwise open native menus for this augmentation.
- Recompute on each submenu open so existing windows are current without adding live observers.

Expected tests/review checks:

- A `Window` menu with empty native `AXChildren` still shows AXWindows-only rows.
- No Window-submenu path performs `kAXPressAction` or `kAXCancelAction` just to populate rows.
- Normal non-Window submenu paths keep existing extraction behavior.

### 5. Explicit action dispatch

Replace hard-coded action execution assumptions where leaf actions are performed.

TDD must prove dispatch, not just representation. Add a pure action request/seam or equivalent focused tests so the implementation would fail if `.raiseAXWindow` still used `kAXPressAction`.

Expected tests:

- `.pressMenuItem` maps to an AX press request/action (`kAXPressAction`).
- `.raiseAXWindow` maps to an AX raise request/action (`kAXRaiseAction`).
- Main-menu action dismissal behavior remains unchanged for normal `.pressMenuItem` rows.
- Submenu/torn-off action behavior remains unchanged for normal `.pressMenuItem` rows.
- Synthesized `.raiseAXWindow` rows do not use checkmark toggling or menu-item press assumptions.

Implementation shape:

- Add a small controller-side dispatcher or pure request builder, for example `MenuActionRequest`, mapping:
  - `.pressMenuItem` → current activate + `kAXPressAction`
  - `.raiseAXWindow` → activate target app + `kAXRaiseAction`
- Keep actual `AXUIElementPerformAction` calls in `Sources/NeXTMenus` controllers/helpers.
- Only add focus/minimized handling if manual evidence shows it is necessary.

Paths to audit:

- `MenuWindowController.executeActionAtRow(_:)`
- `MenuWindowController` fallback leaf action in `showSubmenu(for:at:submenuItems:fallbackElement:)`
- `SubmenuWindowController.performAction(...)`
- `SubmenuWindowController.executeActionAtRow(_:)`

## Verification

Run from the worktree:

1. `git diff --check`
2. `make check-sources`
3. Focused new tests
4. `swift test`
5. `swift build`
6. `make verify`

Manual smoke tests:

- Wireless Diagnostics `Window` submenu does not open/flicker native macOS menus.
- NeXTMenus submenu opening has no new delay.
- If `Info`, `Logs`, `Scan`, and `Performance` windows already exist in Accessibility, they appear in the NeXTMenus `Window` submenu.
- Selecting synthesized rows raises the corresponding window.
- Normal menu actions still work.
- Torn-off submenu actions still work.

## Risks and Mitigations

- **Existing-window boundary:** If the desired Wireless Diagnostics entries are not exposed as `AXWindows` until native menu commands create them, this approach cannot show them. Mitigation: smoke test with the relevant Wireless Diagnostics windows open; if missing, stop and report the OS/app limitation rather than reintroducing native menu opening.
- **Duplicate/localized titles:** Matching by title can collide. Mitigation: dedupe conservatively by exact nonempty title and append only missing synthesized rows.
- **Minimized/hidden windows:** `kAXRaiseAction` may not restore every minimized/hidden window. Mitigation: start with raise-only; add minimized handling only with evidence.
- **Action model breadth:** Adding explicit action semantics touches several action paths. Mitigation: keep the enum small and default to `.pressMenuItem`, with tests covering unchanged normal action behavior.

## Approval Request

After plan review, implement in the dedicated worktree above. Recommended first implementation target is the minimal existing-window synthesis path for top-level `Window` submenus, with no native menu refresh behavior.