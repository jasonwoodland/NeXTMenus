import Cocoa

class SubmenuWindowController: NSWindowController {
    private var submenuWindow: NSWindow!
    private var tableView: HoverTableView!
    private var menuItems: [MenuItem] = []
    private var title: String = ""
    private var targetApp: NSRunningApplication?
    private let rowHeight: CGFloat = 24
    private let titleBarHeight: CGFloat = 28
    private let windowWidth: CGFloat = 180

    // Track window state
    private var isTornOff: Bool = false
    private var initialWindowFrame: NSRect = .zero
    private var isProgrammaticMove: Bool = false
    private var moveDetectionTimer: Timer?

    // Track child submenu window
    private var childSubmenuController: SubmenuWindowController?
    private var childSubmenuRow: Int?
    private var childMoveTimer: Timer?

    // Track global click monitor
    private var globalClickMonitor: Any?

    init(title: String, menuItems: [MenuItem], targetApp: NSRunningApplication?) {
        self.title = title
        self.menuItems = menuItems
        self.targetApp = targetApp

        // Calculate window height based on number of items
        let numberOfRows = menuItems.count
        let contentHeight = CGFloat(numberOfRows) * rowHeight
        let extraPadding: CGFloat = 8 // Additional padding for better spacing
        let windowHeight = contentHeight + titleBarHeight + extraPadding

        // Create window with initial frame (will be positioned when shown)
        let window = NonActivatingWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        self.submenuWindow = window
        window.title = title
        setupWindow()
        setupTableView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWindow() {
        // Hide traffic lights initially (will show close button when torn off)
        submenuWindow.standardWindowButton(.closeButton)?.isHidden = true
        submenuWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
        submenuWindow.standardWindowButton(.zoomButton)?.isHidden = true

        // Make window float on top
        submenuWindow.level = .floating
        submenuWindow.isMovableByWindowBackground = true

        // Enable translucent glass appearance with visible title
        submenuWindow.titlebarAppearsTransparent = true
        submenuWindow.titleVisibility = .visible
        submenuWindow.isOpaque = false
        submenuWindow.backgroundColor = .clear

        // Make sure window appears on all spaces
        submenuWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Set up window drag notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: submenuWindow
        )

        // Set up global click monitor to detect clicks outside the window
        setupGlobalClickMonitor()

        // Watch for application deactivation
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    private func setupGlobalClickMonitor() {
        // Monitor global mouse clicks
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, !self.isTornOff else { return }

            // Get click location
            let clickLocation = event.locationInWindow

            // Check if click is outside this window
            if let screenClickLocation = NSEvent.mouseLocation as CGPoint?,
               !self.submenuWindow.frame.contains(screenClickLocation) {
                // Click was outside - close the submenu
                self.hideWindow()
            }
        }
    }

    @objc private func applicationDidResignActive(_ notification: Notification) {
        // Only close if not torn off
        if !isTornOff {
            hideWindow()
        }
    }

    deinit {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowDidMove(_ notification: Notification) {
        // Ignore moves that are programmatic
        if isProgrammaticMove {
            return
        }

        // Only mark as torn off if the window has actually moved from its initial position
        if !isTornOff {
            let currentFrame = submenuWindow.frame
            let distanceMoved = sqrt(
                pow(currentFrame.origin.x - initialWindowFrame.origin.x, 2) +
                pow(currentFrame.origin.y - initialWindowFrame.origin.y, 2)
            )

            // Only consider it torn off if moved more than 10 pixels
            if distanceMoved > 10 {
                // Cancel any existing timer
                moveDetectionTimer?.invalidate()

                // Set a timer to mark as torn off after movement stops
                // This ensures we only mark as torn off for deliberate user drags
                moveDetectionTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    let currentFrame = self.submenuWindow.frame
                    let distanceMoved = sqrt(
                        pow(currentFrame.origin.x - self.initialWindowFrame.origin.x, 2) +
                        pow(currentFrame.origin.y - self.initialWindowFrame.origin.y, 2)
                    )

                    if !self.isTornOff && distanceMoved > 10 {
                        self.isTornOff = true
                        // Show close button for torn off windows
                        self.submenuWindow.standardWindowButton(.closeButton)?.isHidden = false
                    }
                }
            }
        }

        // If we have child windows, debounce their repositioning
        if childSubmenuController != nil, childSubmenuRow != nil {
            // Cancel any existing timer
            childMoveTimer?.invalidate()

            // Set a timer to reposition children after movement stops
            childMoveTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if let controller = self.childSubmenuController, let row = self.childSubmenuRow {
                    controller.repositionRelativeToParent(self.submenuWindow, alignedToRow: row)
                }
            }
        }
    }

    func repositionRelativeToParent(_ parentWindow: NSWindow, alignedToRow row: Int? = nil) {
        // Only reposition if not torn off
        guard !isTornOff else { return }

        let parentFrame = parentWindow.frame
        let xPos = parentFrame.maxX
        // Align tops: parent's top (maxY) minus child's height gives child's bottom (origin.y)
        let yPos = parentFrame.maxY - submenuWindow.frame.height

        // Mark this as a programmatic move to avoid triggering torn-off state
        isProgrammaticMove = true

        submenuWindow.setFrameOrigin(NSPoint(x: xPos, y: yPos))

        // Update initial frame after repositioning
        initialWindowFrame = submenuWindow.frame

        // Reset flag after a short delay to ensure all notifications have been processed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.isProgrammaticMove = false
        }

        // Recursively reposition child windows
        if let childSubmenuController = childSubmenuController, let childRow = childSubmenuRow {
            childSubmenuController.repositionRelativeToParent(submenuWindow, alignedToRow: childRow)
        }
    }

    private func setupTableView() {
        // Create scroll view with padding for title bar
        guard let contentView = submenuWindow.contentView else { return }

        // Calculate frame to start below the title bar
        let scrollViewFrame = NSRect(
            x: 0,
            y: 0,
            width: contentView.bounds.width,
            height: contentView.bounds.height - titleBarHeight
        )

        let scrollView = NSScrollView(frame: scrollViewFrame)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        // Create table view
        tableView = HoverTableView(frame: scrollView.bounds)
        tableView.autoresizingMask = [.width, .height]
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.rowHeight = rowHeight

        // Add a single column
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MenuItemColumn"))
        column.width = windowWidth
        tableView.addTableColumn(column)

        // Set delegates
        tableView.delegate = self
        tableView.dataSource = self

        // Set up hover callback for drag-over behavior
        tableView.onMouseDraggedOverRow = { [weak self] row in
            self?.handleMouseDraggedOverRow(row)
        }

        // Set up click callback
        tableView.onMouseClickedRow = { [weak self] row in
            self?.handleMouseClickedRow(row)
        }

        // Add table view to scroll view
        scrollView.documentView = tableView

        // Add scroll view to window
        contentView.addSubview(scrollView)
    }

    private func handleMouseDraggedOverRow(_ row: Int) {
        // Check if row is selectable (not disabled or separator)
        guard tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false else {
            return
        }

        let menuItem = menuItems[row]

        // If it's different from current open submenu and not a separator, show it
        if row != childSubmenuRow, !menuItem.isSeparator {
            // Only open submenus on hover, don't execute actions
            if menuItem.hasSubmenu, let element = menuItem.element {
                let submenuItems = MenuExtractor.extractSubmenuItemsOnDemand(from: element)

                if !submenuItems.isEmpty {
                    // Close any existing child submenu
                    childSubmenuController?.hideWindow()

                    // Create and show new child submenu
                    childSubmenuController = SubmenuWindowController(
                        title: menuItem.title,
                        menuItems: submenuItems,
                        targetApp: targetApp
                    )
                    childSubmenuController?.showWindow(rightOf: submenuWindow, alignedToRow: row)
                    childSubmenuRow = row

                    // Update all row highlights
                    for i in 0..<tableView.numberOfRows {
                        updateRowHighlight(forRow: i)
                    }
                }
            }
        }
    }

    func showWindow(rightOf parentWindow: NSWindow, alignedToRow row: Int? = nil) {
        // Position to the right of the parent window with tops aligned
        let parentFrame = parentWindow.frame
        let xPos = parentFrame.maxX
        // Align tops: parent's top (maxY) minus child's height gives child's bottom (origin.y)
        let yPos = parentFrame.maxY - submenuWindow.frame.height

        // Mark this as a programmatic move
        isProgrammaticMove = true

        submenuWindow.setFrameOrigin(NSPoint(x: xPos, y: yPos))

        // Set initial frame after positioning
        initialWindowFrame = submenuWindow.frame

        // Reset flag after a short delay to ensure all notifications have been processed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.isProgrammaticMove = false
        }

        submenuWindow.orderFrontRegardless()
    }

    func hideWindow() {
        // Only hide if not torn off
        guard !isTornOff else { return }

        // Hide child submenu first (unless they're torn off)
        childSubmenuController?.hideWindow()
        childSubmenuController = nil
        childSubmenuRow = nil

        submenuWindow.orderOut(nil)
    }
}

// MARK: - NSTableViewDataSource
extension SubmenuWindowController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return menuItems.count
    }
}

// MARK: - NSTableViewDelegate
extension SubmenuWindowController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellIdentifier = NSUserInterfaceItemIdentifier("MenuItemCell")

        var cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView

        if cell == nil {
            cell = NSTableCellView()
            cell?.identifier = cellIdentifier
            cell?.wantsLayer = true

            // Add background view
            let backgroundView = NSView(frame: CGRect(x: 0, y: 0, width: windowWidth, height: rowHeight))
            backgroundView.wantsLayer = true
            backgroundView.identifier = NSUserInterfaceItemIdentifier("BackgroundView")
            backgroundView.autoresizingMask = [.width, .height]
            cell?.addSubview(backgroundView)

            // Calculate Y offset to center text vertically
            let textHeight: CGFloat = 17
            let yOffset = (rowHeight - textHeight) / 2

            let textField = NSTextField(frame: NSRect(x: 8, y: yOffset, width: windowWidth - 16, height: textHeight))
            textField.isBordered = false
            textField.backgroundColor = .clear
            textField.isEditable = false
            textField.isSelectable = false
            textField.autoresizingMask = [.width]
            textField.drawsBackground = false
            textField.alignment = .left
            textField.usesSingleLineMode = true
            textField.lineBreakMode = .byTruncatingTail

            cell?.addSubview(textField)
            cell?.textField = textField
        }

        // Check if this row has an open submenu
        let isHighlighted = (childSubmenuRow == row)

        // Update background view
        if let backgroundView = cell?.subviews.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("BackgroundView") }) {
            if isHighlighted {
                backgroundView.layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.3).cgColor
            } else {
                backgroundView.layer?.backgroundColor = NSColor.clear.cgColor
            }
        }

        let menuItem = menuItems[row]

        // Handle separators
        if menuItem.isSeparator {
            cell?.textField?.isHidden = true

            // Add separator line if not already added
            let separatorId = NSUserInterfaceItemIdentifier("Separator")
            if cell?.subviews.first(where: { $0.identifier == separatorId }) == nil {
                let separator = NSBox(frame: NSRect(x: 8, y: rowHeight / 2 - 0.5, width: windowWidth - 16, height: 1))
                separator.boxType = .separator
                separator.identifier = separatorId
                separator.autoresizingMask = [.width]
                cell?.addSubview(separator)
            }
        } else {
            cell?.textField?.isHidden = false
            cell?.textField?.stringValue = menuItem.title
            cell?.textField?.font = NSFont.systemFont(ofSize: 13)
            cell?.textField?.textColor = menuItem.isEnabled ? .labelColor : .disabledControlTextColor

            // Remove separator if it exists
            let separatorId = NSUserInterfaceItemIdentifier("Separator")
            cell?.subviews.first(where: { $0.identifier == separatorId })?.removeFromSuperview()
        }

        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = NSTableRowView()
        rowView.isEmphasized = false
        return rowView
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        // Don't allow selection of disabled items or separators
        let menuItem = menuItems[row]
        return menuItem.isEnabled && !menuItem.isSeparator
    }

    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        // Update row background based on whether it has an open submenu
        updateRowHighlight(forRow: row)
    }

    private func updateRowHighlight(forRow row: Int) {
        guard let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) else { return }
        guard let cellView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView else { return }

        let isHighlighted = (childSubmenuRow == row)

        if isHighlighted {
            rowView.isSelected = true
            cellView.backgroundStyle = .emphasized
        } else {
            rowView.isSelected = false
            cellView.backgroundStyle = .normal
        }
    }

    private func handleMouseClickedRow(_ row: Int) {
        // Check if row is selectable (not disabled or separator)
        guard tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false else {
            return
        }

        let menuItem = menuItems[row]

        // Check if clicking on the same item that's already open - toggle it closed
        if childSubmenuRow == row {
            childSubmenuController?.hideWindow()
            childSubmenuController = nil
            childSubmenuRow = nil

            // Update all row highlights
            for i in 0..<tableView.numberOfRows {
                updateRowHighlight(forRow: i)
            }
            return
        }

        // If this item might have submenu items, extract them on-demand
        if menuItem.hasSubmenu, let element = menuItem.element {
            let submenuItems = MenuExtractor.extractSubmenuItemsOnDemand(from: element)

            if !submenuItems.isEmpty {
                // Close any existing child submenu
                childSubmenuController?.hideWindow()

                // Create and show new child submenu
                childSubmenuController = SubmenuWindowController(
                    title: menuItem.title,
                    menuItems: submenuItems,
                    targetApp: targetApp
                )
                childSubmenuController?.showWindow(rightOf: submenuWindow, alignedToRow: row)
                childSubmenuRow = row

                // Update all row highlights
                for i in 0..<tableView.numberOfRows {
                    updateRowHighlight(forRow: i)
                }
            } else {
                // No submenu - this is an action item, execute it
                targetApp?.activate(options: [])
                usleep(50000)
                AXUIElementPerformAction(element, kAXPressAction as CFString)

                // Close any open child submenu
                childSubmenuController?.hideWindow()
                childSubmenuController = nil
                childSubmenuRow = nil

                // Update all row highlights
                for i in 0..<tableView.numberOfRows {
                    updateRowHighlight(forRow: i)
                }
            }
        } else {
            // No submenu - this is an action item, execute it
            if let element = menuItem.element {
                targetApp?.activate(options: [])
                usleep(50000)
                AXUIElementPerformAction(element, kAXPressAction as CFString)
            }

            // Close any open child submenu
            childSubmenuController?.hideWindow()
            childSubmenuController = nil
            childSubmenuRow = nil

            // Update all row highlights
            for i in 0..<tableView.numberOfRows {
                updateRowHighlight(forRow: i)
            }
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0 else { return }

        // Deselect immediately for button-like behavior
        tableView.deselectRow(selectedRow)

        let menuItem = menuItems[selectedRow]

        // Check if clicking on the same item that's already open - toggle it closed
        if let existingChild = childSubmenuController, childSubmenuRow == selectedRow {
            childSubmenuController?.hideWindow()
            childSubmenuController = nil
            childSubmenuRow = nil

            // Update all row highlights
            for i in 0..<tableView.numberOfRows {
                updateRowHighlight(forRow: i)
            }
            return
        }

        // If this item might have submenu items, extract them on-demand
        if menuItem.hasSubmenu, let element = menuItem.element {
            let submenuItems = MenuExtractor.extractSubmenuItemsOnDemand(from: element)

            if !submenuItems.isEmpty {
                // Close any existing child submenu
                childSubmenuController?.hideWindow()

                // Create and show new child submenu
                childSubmenuController = SubmenuWindowController(
                    title: menuItem.title,
                    menuItems: submenuItems,
                    targetApp: targetApp
                )
                childSubmenuController?.showWindow(rightOf: submenuWindow, alignedToRow: selectedRow)
                childSubmenuRow = selectedRow

                // Update all row highlights
                for i in 0..<tableView.numberOfRows {
                    updateRowHighlight(forRow: i)
                }
            } else {
                // No submenu - this is an action item, execute it
                if let element = menuItem.element {
                    // Activate the target application first so the action executes in the right context
                    targetApp?.activate(options: [])

                    // Small delay to ensure activation completes
                    usleep(50000) // 50ms

                    AXUIElementPerformAction(element, kAXPressAction as CFString)
                }

                // Close any open child submenu
                childSubmenuController?.hideWindow()
                childSubmenuController = nil
                childSubmenuRow = nil

                // Update all row highlights
                for i in 0..<tableView.numberOfRows {
                    updateRowHighlight(forRow: i)
                }
            }
        } else {
            // No submenu - this is an action item, execute it
            if let element = menuItem.element {
                // Activate the target application first so the action executes in the right context
                targetApp?.activate(options: [])

                // Small delay to ensure activation completes
                usleep(50000) // 50ms

                AXUIElementPerformAction(element, kAXPressAction as CFString)
            }

            // Close any open child submenu
            childSubmenuController?.hideWindow()
            childSubmenuController = nil
            childSubmenuRow = nil

            // Update all row highlights
            for i in 0..<tableView.numberOfRows {
                updateRowHighlight(forRow: i)
            }
        }
    }
}
