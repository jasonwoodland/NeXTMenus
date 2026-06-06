# Plan: Dynamic Menu Loading and Refresh Fixes

## Objective

Fix two reported dynamic menu loading/update issues as a behavior change separate from the Phase 3 refactors:

1. Some apps show only fallback-style rows such as `Info`, `Hide`, and `Quit` until NeXTMenus is restarted.
2. Wireless Diagnostics' `Window` submenu misses dynamic items such as `Info`, `Logs`, `Scan`, and `Performance`.

## Research Evidence

- `MainMenuRows.count` always includes the app-info row and configured trailing actions, so an empty extracted top-level app menu can still render visible fallback rows.
  - `Sources/NeXTMenusKit/MainMenuRows.swift`
- `AppDelegate.handleActiveApplicationChange(_:)` caches one `MenuWindowController` per PID. Existing cached controllers are reused without re-extracting their top-level menu.
  - `Sources/NeXTMenus/AppDelegate.swift`
- Initial empty extraction only starts a bounded retry loop when the controller is first created. If that retry never succeeds, the cached fallback controller can persist until app termination or NeXTMenus restart.
  - `Sources/NeXTMenus/AppDelegate.swift`
- `MenuExtractor.extractSubmenuItemsOnDemand(from:)` reads `AXChildren` first and only presses the menu item when children are missing/empty. Dynamic `NSMenu` contents can be populated only when the menu is opened, so nonempty stale/static children can prevent dynamic items from appearing.
  - `Sources/NeXTMenus/MenuExtractor.swift`
- When `extractSubmenuItemsOnDemand(from:)` does press, it cancels before `extractSubmenuItems(from:)` recursively reads nested `AXMenu` children. Dynamic children may disappear or remain incomplete by the time recursion runs.
  - `Sources/NeXTMenus/MenuExtractor.swift`
- Submenu controllers work from snapshots and modifier/version caches; they re-extract only on open/switch/modifier changes, not on external menu mutation.
  - `Sources/NeXTMenus/SubmenuWindowController.swift`

## Scope

### In scope

- Retry/re-extract a cached top-level controller when the underlying extracted top-level menu is empty/stale.
- Prevent duplicate retry timers for the same PID.
- Never replace a populated cached menu with an empty retry result.
- Improve on-demand submenu extraction so dynamic submenus are opened before reading their final item list.
- Keep AX/AppKit side effects in `Sources/NeXTMenus` (`AppDelegate`, `MenuWindowController`, `MenuExtractor`).
- Add pure policy to `NeXTMenusKit` only for refresh/retry decisions.

### Out of scope

- Eager full-menu extraction for every app.
- Refreshing already-populated top-level menus on every activation.
- Moving `MenuExtractor` or `NeXTMenusSettings` into `NeXTMenusKit`.
- Changing click, hover, mouse-up/down, torn-off, or submenu presentation semantics.
- Fixing every possible dynamic menu mutation while a submenu is already open.

## Branch and Worktree

- Branch: `fix/dynamic-menu-refresh`
- Worktree: `.worktrees/fix/dynamic-menu-refresh/`

Before creating the worktree, confirm `main` is clean. If not, stop and resolve/confirm first.

## TDD Plan

### 1. Cached empty top-level menu refresh policy

Add tests in `Tests/NeXTMenusKitTests/MenuRefreshPolicyTests.swift` for a pure policy helper, for example:

- Empty extracted top-level menu should be considered stale and eligible for retry.
- Nonempty extracted top-level menu should not be considered stale.
- A pending retry should suppress starting another retry for the same PID.
- Fallback rows such as app-info/trailing actions must not count as a loaded top-level app menu; the decision is based on extracted `menuItems.count`.

Expected RED: missing refresh policy type/API.

Implement in `Sources/NeXTMenusKit/MenuRefreshPolicy.swift` or an existing kit policy file.

### 2. Cached controller re-extraction

Refactor the app-side cache path with the smallest side-effect change:

- Add an internal read-only property on `MenuWindowController`, such as `topLevelMenuItemCount` or `hasLoadedTopLevelMenuItems`, based on the underlying extracted `menuItems` array.
- In `AppDelegate.handleActiveApplicationChange(_:)`, when reusing an existing controller, consult the pure policy and restart `retryMenuExtraction(for:attempt:)` if the cached controller is stale and no retry is already pending for that PID.
- Track pending retry PIDs in `AppDelegate` to avoid duplicate timers.
- Keep the existing initial empty-menu retry behavior for newly created controllers.
- In `retryMenuExtraction`, clear pending state when the retry succeeds, exhausts, or the app/controller disappears.
- Continue applying only nonempty retry results via `applyFullMenu(appMenuItem:menuItems:)`; do not replace populated menus with empty extraction results.

Test coverage should primarily exercise the pure policy. If feasible without destabilizing the package, add a narrow app-target test for the retry decision using fakes. If importing the executable target for tests is not practical, keep app-side verification to code review plus manual smoke and avoid broad package restructuring.

### 3. Dynamic submenu extraction sequence

Add focused tests for the on-demand submenu extraction sequence. Preferred approach:

- Add a minimal AX seam inside `Sources/NeXTMenus/MenuExtractor.swift`, such as an internal `AXMenuReading` protocol plus a system implementation.
- Keep the public/default `MenuExtractor.extractSubmenuItemsOnDemand(from:)` API intact.
- Add tests that use a fake reader to assert:
  - Extraction presses/opens the menu even when initial `AXChildren` is nonempty.
  - Recursive `AXMenu` child reads happen while the menu is still open, before `AXCancel`.
  - If pressing/opening fails or produces no improved children, extraction falls back to the initial children rather than returning nothing.

Implementation target:

- Change `extractSubmenuItemsOnDemand(from:)` to capture initial children, press/open for a dynamic refresh, wait briefly, read refreshed children, recursively extract while still open, and use `defer` to cancel after recursive extraction completes.
- Avoid skipping the press solely because initial `AXChildren` is nonempty.
- Prefer refreshed children when nonempty; fall back to initial children if refresh fails.

If app-target tests cannot be added cleanly under SwiftPM, keep the AX seam small and verify this sequence with code review plus manual smoke. Do not move `MenuExtractor` into `NeXTMenusKit`.

## Verification

Run from the worktree:

1. `git diff --check`
2. `make check-sources`
3. Focused tests for the new policy/extraction coverage
4. `swift test`
5. `swift build`
6. `make verify`

Manual smoke tests:

- Confirm previously fallback-only apps recover their full top-level menus without restarting NeXTMenus.
- Confirm Wireless Diagnostics `Window` submenu includes dynamic items such as `Info`, `Logs`, `Scan`, and `Performance`.
- Smoke normal submenu opening, leaf actions, and torn-off submenu behavior to ensure interaction semantics are unchanged.

## Risks and Mitigations

- Opening menus during extraction can be visually disruptive. Mitigation: keep the existing lazy/on-demand behavior and cancel promptly after recursive reads.
- A fixed 50 ms wait may still be too short for some dynamic menus. Mitigation: start with the smallest behavior change, but allow a bounded slightly longer wait or short main-runloop spin if RED/manual evidence requires it.
- Re-extracting on every activation could be slow. Mitigation: only retry cached controllers whose extracted top-level menu is empty/stale.
- App-target unit tests may require a package test-target adjustment. Mitigation: keep package changes minimal; if not feasible, rely on pure policy tests, code review, and manual AX smoke for `MenuExtractor`.

## Approval Request

After plan review, implement this as a behavior fix in the dedicated worktree above. Recommended approach: keep both fixes in the same branch because they address the same dynamic loading/update class, but commit them as clearly scoped changes if the diff grows.
