# Plan: Generic Static Menu Title Repair for Blank AX Menu Items

## Objective

Make NeXTMenus match native menu rows more closely without opening native macOS menus by repairing blank runtime `AXMenuItem` titles from the target app's static main-menu nib metadata.

This is motivated by Wireless Diagnostics: its native `Window` menu exposes enabled command elements through Accessibility without opening the menu, but several command rows have nil/blank `AXTitle`. The same rows' `AXIdentifier` values match `NSMenuItem.identifier` values in the app's static `MainMenu.nib`, where the titles are present.

## Evidence

Runtime no-press AX probe against Wireless Diagnostics found:

- The `Window` menu tree is available through AX without pressing/opening the parent menu.
- The command rows are real, enabled `AXMenuItem`s with `AXPress` actions.
- `Assistant` has title `_NS:50` / `Assistant`.
- The following command rows are enabled but blank/nil-titled:
  - `_NS:54`
  - `_NS:59`
  - `_NS:64`
  - `_NS:69`
  - `_NS:74`
  - `_NS:79`
  - `_NS:84`
- Generic AX metadata on those blank rows exposes no recoverable user-visible names: `AXTitle` is nil/blank, no useful `AXDescription`, `AXValue`, label, or parameterized name is present.
- Directly pressing child AX menu item `_NS:54` succeeded and opened `Info`, without pressing/opening the parent `Window` menu.

Static nib probe found that loading the app bundle with `NSNib(nibNamed: "MainMenu", bundle:)` instantiates an `NSMenu` whose `Window` menu contains matching `NSMenuItem.identifier` values and titles:

- `_NS:54` -> `Info`
- `_NS:59` -> `Logs`
- `_NS:64` -> `Scan`
- `_NS:69` -> `Performance`
- `_NS:74` -> `Sniffer`
- `_NS:79` -> `Sidecar`
- `_NS:84` -> `Diagnostics`

This provides a generic fallback candidate: match runtime AX identifiers to static menu item identifiers, copy only missing titles, and keep the live AX element for invocation.

## Scope

### In scope

- Capture `AXIdentifier` from runtime AX menu items into `MenuItem`.
- Add a pure static-title repair helper in `NeXTMenusKit`.
- Add an app-side static menu metadata loader in `Sources/NeXTMenus` that:
  - locates the target app's main menu nib generically from its bundle,
  - instantiates it with `instantiate(withOwner: nil, topLevelObjects:)`,
  - traverses only `NSMenu` / `NSMenuItem` title, identifier, and submenu structure into plain value metadata,
  - performs no validation, actions, native menu opening, `AXPress`, or `AXCancel`,
  - caches successful metadata and loading failures per target bundle/version/nib path.
- Repair only blank/nil/separator-like runtime titles when an unambiguous static identifier match exists.
- Preserve runtime AX order, live AX elements, enabled state, submenu/action behavior, keyboard metadata, marks, and action kind.
- Layer static title repair before existing `AXWindows` synthesis in both main and submenu controller presentation paths.
- Keep normal non-blank runtime titles authoritative.

### Out of scope

- App-specific hardcoded identifier/title maps.
- Opening or pressing native parent menus to populate content.
- OCR/screenshot parsing.
- Private/in-process injection or direct AppKit calls into the target process.
- Replacing dynamic runtime state with static nib state.
- Creating windows that are not represented by live command elements or `AXWindows`.

## Design

### 1. Runtime identifier capture

Add `axIdentifier: String?` to `MenuItem` as a defaulted final initializer parameter for source compatibility. During AX extraction, read `AXIdentifier` for top-level and submenu items.

All `MenuItem` factory/helper sites should set it deliberately:

- Runtime AX items: copied `AXIdentifier` or `nil`.
- Synthesized `AXWindows` rows: `nil`.
- Separator helpers: `nil`.
- Test helpers: default `nil` unless exercising identifier repair.

### 2. Static menu metadata

Add a small app-side representation, for example:

```swift
struct StaticMenuItemMetadata {
    let identifier: String?
    let title: String
    let submenuItems: [StaticMenuItemMetadata]
}
```

Load from `Bundle(path:)` / target app bundle URL and the bundle's `NSMainNibFile` when available, falling back to `MainMenu`.

Threading requirement:

- `NSNib` instantiation and all `NSMenu` / `NSMenuItem` traversal must run on the main thread.
- The loader returns/caches plain value metadata only.
- Background submenu extraction paths must use cached value metadata only and must not instantiate or traverse AppKit menu objects.

Safety/no-op rules:

- Use `instantiate(withOwner: nil, topLevelObjects:)`.
- Do not set `NSApp.mainMenu`, display menus, ask AppKit to update/validate menu items, or invoke actions.
- Collect only `NSMenu` / `NSMenuItem` values into plain metadata.
- If bundle/nib loading fails, no top-level menu is found, an identifier is absent, or duplicate identifiers map ambiguously, repair no-ops for affected identifiers.
- Cache loading failures to avoid repeated work.

### 3. Pure repair helper

Add `StaticMenuTitleRepair` in `NeXTMenusKit`:

- Input: runtime `[MenuItem]`, static metadata tree or flattened identifier/title map.
- If runtime title is nonblank, keep it unchanged.
- If runtime title is blank/separator-like and `axIdentifier` has exactly one static title match, copy the static title and set `isSeparator = false`.
- Recurse into submenu items.
- Preserve every other field, especially `element`, `isEnabled`, `hasSubmenu`, `submenuItems`, shortcut metadata, `markChar`, `actionKind`, and `axIdentifier`.

### 4. Shared presentation layering

Current branch `c597609` has Window presentation helpers in both `MenuWindowController` and `SubmenuWindowController`:

- read no-press AX children,
- synthesize `AXWindows`,
- merge with `WindowSubmenuSynthesis`.

Update both paths, preferably through a shared app-side helper, so `Window` presentation is consistently:

1. Read no-press AX children.
2. Repair blank titles from cached static metadata.
3. Synthesize `AXWindows` rows.
4. Merge with `WindowSubmenuSynthesis`.

This keeps command rows in the runtime AX order and leaves `AXWindows` as a fallback for already-existing windows not present as native command/window rows.

The repaired native command row must keep `.pressMenuItem`, because it invokes the live AX menu-item element. A synthesized `AXWindows` row keeps `.raiseAXWindow`.

## TDD Plan

### Pure tests

Add tests for `StaticMenuTitleRepair`:

- Repairs a blank runtime title by matching `axIdentifier` to static title.
- Does not overwrite a nonblank runtime title.
- Preserves runtime order and all runtime metadata/action kind.
- No-ops for missing identifier, missing static match, or ambiguous duplicate identifier.
- Repairs nested submenu items.
- Branch-context test: a blank native `Window` item with `axIdentifier` repaired to `Info` suppresses a synthesized `AXWindows` `Info` row during `WindowSubmenuSynthesis`, preserving the native `.pressMenuItem` row instead of appending a duplicate `.raiseAXWindow` row.

### App-side seam tests

If practical without real target-app AX side effects, add tests for traversing a programmatically-created `NSMenu` into static metadata. Avoid depending on Wireless Diagnostics in unit tests.

### Expected RED

- `MenuItem` has no `axIdentifier`.
- `StaticMenuTitleRepair` does not exist.
- Static menu metadata loader/cache does not exist.
- Window presentation in both controllers does not repair blank titles before AXWindows synthesis.

## Verification

Run from `.worktrees/fix/window-submenu-axwindows`:

1. Focused new tests
2. `git diff --check`
3. `make check-sources`
4. `swift test`
5. `swift build`
6. `make verify`
7. Independent code review

Manual smoke:

- Wireless Diagnostics `Window` submenu shows `Assistant`, `Info`, `Logs`, `Scan`, `Performance`, `Sniffer`, `Sidecar`, `Diagnostics` in the native command section, not only open-window rows at the bottom.
- Selecting a repaired command row opens the corresponding panel without the parent native menu flickering open.
- Existing open windows still show/raise correctly.
- Normal menu rows in other apps remain unchanged.

## Risks and Mitigations

- **Nib unarchive side effects:** Loading a foreign nib may instantiate objects. Mitigate by using nil owner, not installing/displaying menus, collecting only menu metadata, caching failures, and no-oping on errors.
- **Main-thread AppKit constraints:** `NSNib` and `NSMenu` traversal must happen on main thread. Mitigate with main-thread cache population and background use of value metadata only.
- **Static vs dynamic mismatch:** Static nib titles may not reflect dynamic runtime changes. Mitigate by only repairing blank runtime titles; nonblank AX titles remain authoritative.
- **Identifier instability:** `_NS:*` identifiers may change across OS/app versions. Mitigate by matching the current runtime identifier to the current installed app's static nib at runtime, not hardcoding values.
- **Ambiguous identifiers:** Duplicate identifiers could map to different titles. Mitigate by no-op on ambiguity.
- **Localization:** Loading the target bundle's main-menu nib should use the installed localized resources. Verify smoke in the user's locale.

## Recommendation

Proceed with this generic static-title repair as the next implementation slice. Keep the current `AXWindows` action semantics work as secondary fallback, but make repaired native AX command rows the primary solution for Wireless Diagnostics' missing `Window` commands.
