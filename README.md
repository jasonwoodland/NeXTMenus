# NextMenus

A macOS application that displays the menu bar items of the currently active application in a floating window.

## Features

- Observes the currently active macOS application
- Displays a floating window in the top-left corner with the active app's menu bar items
- Window title shows the active application name
- "Info" menu appears at the top of the list
- Traffic lights (close/minimize/maximize buttons) are hidden
- Window automatically shows/hides based on active application
- Always stays on top of other windows

## Requirements

- macOS 13.0 or later
- Accessibility permissions (the app will prompt you on first launch)

## Building

### Option 1: Using Xcode
1. Open the project in Xcode
2. Select the NextMenus scheme
3. Build and run (⌘R)

### Option 2: Using Swift Package Manager
```bash
swift build
```

To run:
```bash
swift run
```

Or build and run the executable:
```bash
swift build -c release
.build/release/NextMenus
```

## Permissions

On first launch, the app will request Accessibility permissions. You need to:
1. Go to System Settings > Privacy & Security > Accessibility
2. Enable permissions for NextMenus

Without these permissions, the app cannot read menu bar items from other applications.

## How It Works

- **ApplicationObserver**: Monitors active application changes using NSWorkspace notifications
- **MenuExtractor**: Uses Accessibility APIs to extract menu bar items from the active application
- **MenuWindowController**: Manages the floating window that displays the menu items
- **AppDelegate**: Coordinates the components and handles application lifecycle

## Notes

- The app runs as an accessory (doesn't appear in the Dock)
- The window appears on all spaces
- Menu items are displayed but not interactive (for display purposes only)
