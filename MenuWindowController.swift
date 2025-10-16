import Cocoa

class MenuWindowController: NSWindowController {
    private var menuWindow: NSWindow!
    private var tableView: NSTableView!
    private var menuItems: [MenuItem] = []
    private var appMenuItem: MenuItem?
    private var appName: String = ""
    private var targetApp: NSRunningApplication?
    private let rowHeight: CGFloat = 24
    private let titleBarHeight: CGFloat = 28
    private let windowWidth: CGFloat = 180

    // Track child submenu window
    private var childSubmenuController: SubmenuWindowController?
    private var childSubmenuRow: Int?

    // Track window movement completion
    private var moveTimer: Timer?

    init(appName: String, appMenuItem: MenuItem?, menuItems: [MenuItem], targetApp: NSRunningApplication) {
        self.appName = appName
        self.appMenuItem = appMenuItem
        self.menuItems = menuItems
        self.targetApp = targetApp

        // Calculate window height based on number of items
        // Add 1 for the "Info" row (app menu)
        let numberOfRows = menuItems.count + 1
        let contentHeight = CGFloat(numberOfRows) * rowHeight
        let extraPadding: CGFloat = 16 // Additional padding for better spacing
        let windowHeight = contentHeight + titleBarHeight + extraPadding

        // Create window with initial frame (will be positioned when shown)
        let window = NonActivatingWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        self.menuWindow = window
        window.title = appName
        setupWindow()
        setupTableView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWindow() {
        // Hide traffic lights
        menuWindow.standardWindowButton(.closeButton)?.isHidden = true
        menuWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
        menuWindow.standardWindowButton(.zoomButton)?.isHidden = true

        // Make window float on top
        menuWindow.level = .floating
        menuWindow.isMovableByWindowBackground = true

        // Enable translucent glass appearance with visible title
        menuWindow.titlebarAppearsTransparent = true
        menuWindow.titleVisibility = .visible
        menuWindow.isOpaque = false
        menuWindow.backgroundColor = .clear

        // Make sure window appears on all spaces
        menuWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Set up window drag notification to reposition child windows
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidEndLiveResize(_:)),
            name: NSWindow.didEndLiveResizeNotification,
            object: menuWindow
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: menuWindow
        )
    }

    @objc private func windowDidMove(_ notification: Notification) {
        // Cancel any existing timer
        moveTimer?.invalidate()

        // Set a timer to reposition children after movement stops
        // This ensures we only reposition when drag is complete, not during drag
        moveTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if let childSubmenuController = self.childSubmenuController, let row = self.childSubmenuRow {
                childSubmenuController.repositionRelativeToParent(self.menuWindow, alignedToRow: row)
            }
        }
    }

    @objc private func windowDidEndLiveResize(_ notification: Notification) {
        // Reposition child submenu when main window finishes resizing
        if let childSubmenuController = childSubmenuController, let row = childSubmenuRow {
            childSubmenuController.repositionRelativeToParent(menuWindow, alignedToRow: row)
        }
    }

    private func setupTableView() {
        // Create scroll view with padding for title bar
        guard let contentView = menuWindow.contentView else { return }

        // Calculate frame to start below the title bar
        let scrollViewFrame = NSRect(
            x: 0,
            y: 0,
            width: contentView.bounds.width,
            height: contentView.bounds.height - titleBarHeight
        )

        let scrollView = NSScrollView(frame: scrollViewFrame)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        // Create table view
        tableView = NSTableView(frame: scrollView.bounds)
        tableView.autoresizingMask = [.width, .height]
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.rowHeight = rowHeight
        // tableView.selectionHighlightStyle = .none

        // Add a single column
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MenuItemColumn"))
        column.width = windowWidth
        tableView.addTableColumn(column)

        // Set delegates
        tableView.delegate = self
        tableView.dataSource = self

        // Add table view to scroll view
        scrollView.documentView = tableView

        // Add scroll view to window
        contentView.addSubview(scrollView)
    }

    func showWindow() {
        // Get the screen containing the mouse pointer (current screen)
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main

        guard let screen = screen else {
            return
        }

        // Position at top-left (0, 0) of the screen, accounting for menu bar
        let menuBarHeight = screen.frame.height - screen.visibleFrame.height - screen.visibleFrame.origin.y
        let windowHeight = menuWindow.frame.height

        menuWindow.setFrameOrigin(NSPoint(
            x: screen.frame.origin.x,
            y: screen.frame.maxY - windowHeight - menuBarHeight
        ))

        menuWindow.orderFrontRegardless()
    }

    func hideWindow() {
        // Hide child submenu first
        childSubmenuController?.hideWindow()
        childSubmenuController = nil

        menuWindow.orderOut(nil)
    }
}

// MARK: - NSTableViewDataSource
extension MenuWindowController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        // Add 1 for the "Info" row
        return menuItems.count + 1
    }
}

// MARK: - NSTableViewDelegate
extension MenuWindowController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellIdentifier = NSUserInterfaceItemIdentifier("MenuItemCell")

        var cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView

        if cell == nil {
            cell = NSTableCellView()
            cell?.identifier = cellIdentifier

            let textField = NSTextField(frame: NSRect(x: 8, y: 0, width: windowWidth - 16, height: rowHeight))
            textField.isBordered = false
            textField.backgroundColor = .clear
            textField.isEditable = false
            textField.isSelectable = false
            textField.autoresizingMask = [.width]

            cell?.addSubview(textField)
            cell?.textField = textField
        }

        // First row is "Info" (the app menu)
        if row == 0 {
            cell?.textField?.stringValue = "Info"
            cell?.textField?.font = NSFont.systemFont(ofSize: 13)
            cell?.textField?.textColor = appMenuItem?.isEnabled ?? true ? .labelColor : .disabledControlTextColor
        } else {
            let menuItem = menuItems[row - 1]
            cell?.textField?.stringValue = menuItem.title
            cell?.textField?.font = NSFont.systemFont(ofSize: 13)
            cell?.textField?.textColor = menuItem.isEnabled ? .labelColor : .disabledControlTextColor
        }

        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return true
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0 else { return }

        // Deselect immediately for button-like behavior
        tableView.deselectRow(selectedRow)

        // Get the menu item
        let menuItem: MenuItem?
        if selectedRow == 0 {
            // First row is "Info" (the app menu)
            menuItem = appMenuItem
        } else {
            menuItem = menuItems[selectedRow - 1]
        }

        guard let menuItem = menuItem else { return }

        // Show submenu at the right edge of the window
        showSubmenu(for: menuItem, at: selectedRow)
    }

    private func showSubmenu(for menuItem: MenuItem, at row: Int) {
        guard let element = menuItem.element else { return }

        // Check if clicking on the same item that's already open - toggle it closed
        if let existingChild = childSubmenuController, childSubmenuRow == row {
            childSubmenuController?.hideWindow()
            childSubmenuController = nil
            childSubmenuRow = nil
            return
        }

        // Extract submenu items on-demand
        let submenuItems = MenuExtractor.extractSubmenuItemsOnDemand(from: element)

        // If this item has submenu items, show child submenu window
        if !submenuItems.isEmpty {
            // Close any existing child submenu
            childSubmenuController?.hideWindow()

            // Create and show new child submenu
            childSubmenuController = SubmenuWindowController(
                title: menuItem.title,
                menuItems: submenuItems,
                targetApp: targetApp
            )
            childSubmenuController?.showWindow(rightOf: menuWindow, alignedToRow: row)
            childSubmenuRow = row
        } else {
            // No submenu - this is an action item, execute it
            // Activate the target application first so the action executes in the right context
            targetApp?.activate(options: [])

            // Small delay to ensure activation completes
            usleep(50000) // 50ms

            AXUIElementPerformAction(element, kAXPressAction as CFString)

            // Close any open child submenu
            childSubmenuController?.hideWindow()
            childSubmenuController = nil
            childSubmenuRow = nil
        }
    }
}
