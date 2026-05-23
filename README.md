# NeXTMenus

NeXTMenus is a macOS reimplementation experiment inspired by the application menus in the NeXTSTEP operating system.

## Features

- Shows the active application's menus in a floating menu
- Uses an **Info** menu as the application menu, followed by the app's other menus
- Match macOS's native menu bar styling of disabled items, separators, checkmarks, submenu arrows, and keyboard shortcuts
- Submenus can be torn off into standalone floating menus
- Supports modifier-sensitive menu items, so alternates can appear when holding keys like Option
- Follows the frontmost app and hides when that app is in fullscreen

## Requirements

- macOS 13 or later
- Accessibility permission enabled for NeXTMenus

## Accessibility permission

On first launch, NeXTMenus asks for Accessibility access. Without it, macOS will not allow the app to read or invoke other applications' menus.

Enable it in:

**System Settings → Privacy & Security → Accessibility**

## Build and run

### Swift Package Manager

```bash
swift build
swift run
```

Release build:

```bash
swift build -c release
swift run -c release
```

### Xcode

Open `Package.swift` in Xcode, then build and run the `NextMenus` app target.
