import Cocoa

class MenuWindowController: NSWindowController {
    private var menuWindow: NSWindow!
    private var tableView: HoverTableView!
    private var menuItems: [MenuItem] = []
    private var appMenuItem: MenuItem?
    private var appName: String = ""
    private var targetApp: NSRunningApplication?
    private let rowHeight: CGFloat = 24
    private let titleBarHeight: CGFloat = 28
    private let windowWidth: CGFloat = 180
    // Small breathing room below the last row so it isn't flush with the edge
    private static let bottomMargin: CGFloat = 8

    // Track child submenu window
    private var childSubmenuController: SubmenuWindowController?
    private var childSubmenuRow: Int?

    // Submenu windows the user has torn off; retained so they stay on screen.
    private var detachedControllers: [SubmenuWindowController] = []

    // True while the pointer is in a child submenu rather than this menu.
    private var childHasMouse = false

    // Track window movement completion
    private var moveTimer: Timer?

    // State management for menu interactions
    private var hoveredRow: Int? // Currently highlighted row (visual only)
    private var isDragging: Bool = false // True while a click-drag is in progress

    // Track local event monitor for cross-window drag
    private var localDragMonitor: Any?

    // Modifier key tracking
    private var currentModifierFlags: NSEvent.ModifierFlags = []
    private var modifierMonitor: Any?
    private var menuItemsVersion = 0
    private var visibleMenuItemsCache: (state: MenuModifierState, version: Int, items: [MenuItem])?

    // Cached visible menu items based on current modifiers. Filtering is on
    // hot table/highlight paths, so keep it O(n) and recompute only when the
    // source menu or relevant modifier state changes.
    private var visibleMenuItems: [MenuItem] {
        let state = MenuModifierState(flags: currentModifierFlags)
        if let cache = visibleMenuItemsCache,
           cache.state == state,
           cache.version == menuItemsVersion {
            return cache.items
        }

        let items = MenuItemVisibility.visibleItems(from: menuItems,
                                                    modifierState: state,
                                                    trimSeparators: false)
        visibleMenuItemsCache = (state, menuItemsVersion, items)
        return items
    }

    private func invalidateVisibleMenuItemsCache() {
        visibleMenuItemsCache = nil
    }

    init(appName: String, appMenuItem: MenuItem?, menuItems: [MenuItem], targetApp: NSRunningApplication) {
        self.appName = appName
        self.appMenuItem = appMenuItem
        self.menuItems = menuItems
        self.targetApp = targetApp

        // Calculate window height based on number of items
        // Add 1 for the "Info" row (app menu)
        let numberOfRows = menuItems.count + 1
        let contentHeight = CGFloat(numberOfRows) * rowHeight
        let windowHeight = contentHeight + titleBarHeight + Self.bottomMargin

        // Create window with initial frame (will be positioned when shown)
        let window = NonActivatingWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        self.menuWindow = window
        window.title = appName
        setupWindow()
        setupTableView()

        // Size the window precisely to the table's content geometry
        tableView.reloadData()
        resizeWindowToFitContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWindow() {
        // Hide traffic lights
        menuWindow.standardWindowButton(.closeButton)?.isHidden = true
        menuWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
        menuWindow.standardWindowButton(.zoomButton)?.isHidden = true

        // Float above all application windows, like a real menu
        menuWindow.level = .popUpMenu
        menuWindow.isMovableByWindowBackground = true

        // Keep the title visible while using glass rendering by default.
        // Low-power opaque drawing can be enabled with NEXTMENUS_LOW_POWER=1.
        menuWindow.titlebarAppearsTransparent = true
        menuWindow.titleVisibility = .visible
        menuWindow.isOpaque = !NextMenusRendering.useGlassEffects
        menuWindow.backgroundColor = NextMenusRendering.useGlassEffects ? .clear : NextMenusRendering.windowBackgroundColor

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

        // Set up local event monitor for mouse drags to handle cross-window hovering
        setupDragMonitor()

        // Set up modifier key monitoring
        setupModifierMonitor()
    }

    private func setupDragMonitor() {
        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self = self else { return event }

            let mouseLocation = NSEvent.mouseLocation

            // Check if we have a child window open
            guard let childController = self.childSubmenuController,
                  let childWindow = childController.window,
                  childWindow.frame.contains(mouseLocation) else {
                return event
            }

            let childRow = childController.getTableView().rowAtScreenPoint(mouseLocation)

            if event.type == .leftMouseDragged {
                // Forward drag to child (no makeKey - avoids a focus flicker)
                childController.handleDragFromParent(at: childRow)
                // Clear parent hover
                self.hoveredRow = nil
                self.updateAllRowHighlights()
            } else if event.type == .leftMouseUp {
                // Forward mouse up to child
                childController.handleMouseUpFromParent(at: childRow)
            }

            return event
        }
    }

    private func setupModifierMonitor() {
        // Global monitor: the windows are non-activating panels, so this app is
        // never the active app — flagsChanged events go to the active app, and
        // a local monitor would never see them.
        modifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }

            // Track if modifiers have changed
            let newModifierFlags = event.modifierFlags
            if self.currentModifierFlags != newModifierFlags {
                self.currentModifierFlags = newModifierFlags
                self.invalidateVisibleMenuItemsCache()

                // Don't re-extract top-level menu items since they typically don't change
                // The submenu items will be re-extracted when opened

                // Reload the table to show/hide alternate menu items
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                    self.resizeWindowToFitContent()

                    // Also notify child submenu to update if it exists
                    self.childSubmenuController?.updateModifierFlags(newModifierFlags)
                }
            }
        }
    }

    deinit {
        if let monitor = localDragMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = modifierMonitor {
            NSEvent.removeMonitor(monitor)
        }
        NotificationCenter.default.removeObserver(self)
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

        // Scroll view fills the area below the title bar, down to the window
        // bottom. The window is `bottomMargin` taller than the rows, so that
        // margin shows as empty space below the last (top-anchored) row.
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
        tableView = HoverTableView(frame: scrollView.bounds)
        // Width-only: as a scroll-view documentView the table's height must
        // track its rows, not get stretched to the clip (which over-scrolls).
        tableView.autoresizingMask = [.width]
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.rowHeight = rowHeight
        // .plain: rows are flush to the window edges. The rounded highlight is
        // drawn by a per-cell view (see viewFor / updateRowHighlight).
        tableView.style = .plain

        // Add a single column
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MenuItemColumn"))
        column.width = windowWidth
        tableView.addTableColumn(column)

        // Set delegates
        tableView.delegate = self
        tableView.dataSource = self

        // Set up mouse callbacks
        tableView.onMouseMoved = { [weak self] row in
            self?.handleMouseMoved(row)
        }

        tableView.onMouseDown = { [weak self] row in
            self?.handleMouseDown(row)
        }

        tableView.onMouseDraggedOverRow = { [weak self] row in
            self?.handleMouseDragged(row)
        }

        tableView.onMouseUp = { [weak self] row, wasDragged in
            self?.handleMouseUp(row, wasDragged: wasDragged)
        }

        tableView.onMouseLongPressReleased = { [weak self] row in
            self?.handleMouseLongPressReleased(row)
        }

        tableView.onMouseExited = { [weak self] in
            self?.handleMouseExited()
        }

        // Add table view to scroll view
        scrollView.documentView = tableView

        // Add scroll view to window
        contentView.addSubview(scrollView)
    }

    // MARK: - Mouse Event Handlers

    // Handle mouse hover (no button pressed) - visual highlight only
    private func handleMouseMoved(_ row: Int) {
        // Pointer is back in the main menu - re-emphasize its open-submenu row
        if childHasMouse {
            childHasMouse = false
            updateAllRowHighlights()
        }
        let rowChanged = hoveredRow != row
        if rowChanged || isDragging {
            isDragging = false
            hoveredRow = row
            updateAllRowHighlights()
        }
        // Once a submenu is open, hovering a sibling switches to its submenu
        if rowChanged, childSubmenuRow != nil {
            updateOpenSubmenu(forHoveredRow: row)
        }
    }

    // Pointer left the table - clear the hover highlight (the open-submenu
    // row stays highlighted via childSubmenuRow).
    private func handleMouseExited() {
        if hoveredRow != nil {
            hoveredRow = nil
            updateAllRowHighlights()
        }
    }

    // Re-orders the open submenu chain above this window; the deepest one
    // becomes key. Called after a click, which would otherwise raise this
    // window on top of its own submenu.
    func raiseSubmenuChain() {
        childSubmenuController?.bringChainToFront()
    }

    // Handle mouse down - open the submenu immediately
    private func handleMouseDown(_ row: Int) {
        // A click raises this window above its open submenu; re-assert the
        // chain on top afterwards so the submenu stays focused/visible.
        defer {
            DispatchQueue.main.async { [weak self] in self?.raiseSubmenuChain() }
        }
        guard row >= 0 else { return }
        guard tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false else { return }

        let menuItem: MenuItem?
        if row == 0 {
            menuItem = appMenuItem
        } else {
            menuItem = menuItems[row - 1]
        }

        guard let menuItem = menuItem, !menuItem.isSeparator else { return }
        showSubmenu(for: menuItem, at: row)
    }

    // Handle mouse drag (button held) - open menus while dragging
    private func handleMouseDragged(_ row: Int) {
        // Only clear when the pointer is over a row of this menu; during a
        // drag this still fires (mouse capture) when the pointer is in a
        // child submenu, where row is -1.
        if row >= 0, childHasMouse {
            childHasMouse = false
            updateAllRowHighlights()
        }
        let rowChanged = hoveredRow != row
        if rowChanged || !isDragging {
            isDragging = true
            hoveredRow = row
            updateAllRowHighlights()
        }
        // Always (not only on row change), so a submenu re-opens if the
        // click-drag's initial mouse-down toggled it closed.
        updateOpenSubmenu(forHoveredRow: row)
    }

    // Switches the open submenu to the hovered row. A row of -1 means the
    // pointer is off the menu items - the submenu is left open only if the
    // pointer is over the child window itself.
    private func updateOpenSubmenu(forHoveredRow row: Int) {
        if row < 0 {
            // Dragging off the menu items: close the submenu unless the
            // pointer is over the child window.
            if isDragging, childSubmenuRow != nil,
               !(childSubmenuController?.window?.frame.contains(NSEvent.mouseLocation) ?? false) {
                collapseSubmenus()
            }
            return
        }
        if childSubmenuRow == row { return }
        guard tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false else { return }
        let menuItem: MenuItem?
        if row == 0 {
            menuItem = appMenuItem
        } else {
            menuItem = visibleMenuItems[row - 1]
        }
        guard let menuItem = menuItem, !menuItem.isSeparator else { return }
        showSubmenu(for: menuItem, at: row)
    }

    // Expose tableView for cross-window detection
    func getTableView() -> HoverTableView {
        return tableView
    }

    // Helper to update all row highlights
    private func updateAllRowHighlights() {
        for i in 0..<tableView.numberOfRows {
            updateRowHighlight(forRow: i)
        }
    }

    func showWindow() {
        menuWindow.orderFrontRegardless()
    }

    // Replace the menu items with a fully pre-extracted tree, once the
    // background extraction has finished.
    func applyFullMenu(appMenuItem: MenuItem?, menuItems: [MenuItem]) {
        self.appMenuItem = appMenuItem
        self.menuItems = menuItems
        menuItemsVersion += 1
        invalidateVisibleMenuItemsCache()
        tableView.reloadData()
        resizeWindowToFitContent()
    }

    // Total height of all rows, read from the table's actual layout geometry
    // rather than recomputed from row counts.
    private func tableContentHeight() -> CGFloat {
        let count = tableView.numberOfRows
        guard count > 0 else { return 0 }
        return tableView.rect(ofRow: count - 1).maxY
    }

    // Resize the window so it exactly fits the current table content.
    private func resizeWindowToFitContent() {
        let contentH = tableContentHeight()
        let height = contentH + titleBarHeight + Self.bottomMargin
        var frame = menuWindow.frame
        frame.origin.y += frame.size.height - height  // keep the top edge fixed
        frame.size.height = height
        menuWindow.setFrame(frame, display: true)
        // Pin the table to its content height. As a scroll-view documentView
        // it doesn't auto-shrink when the clip does, so a stale taller frame
        // would let the scroll view scroll past the rows.
        tableView.frame.size.height = contentH
    }

    func resetPosition() {
        // Get the screen containing the mouse pointer (current screen)
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main

        guard let screen = screen else {
            return
        }

        // Position 8pt in from the top-left corner of the screen
        let windowHeight = menuWindow.frame.height
        let inset: CGFloat = 8

        menuWindow.setFrameOrigin(NSPoint(
            x: screen.frame.origin.x + inset,
            y: screen.frame.maxY - windowHeight - inset
        ))

    }

    func hideWindow() {
        // Hide child submenu first
        childSubmenuController?.hideWindow()
        childSubmenuController = nil
        childSubmenuRow = nil
        hoveredRow = nil

        menuWindow.orderOut(nil)
    }

    // Collapses the whole submenu chain back to this main menu window.
    func collapseSubmenus() {
        childSubmenuController?.hideWindow()
        childSubmenuController = nil
        childSubmenuRow = nil
        updateAllRowHighlights()
    }

    // Creates a child submenu controller and wires up its callbacks.
    private func makeChildController(title: String, menuItems: [MenuItem],
                                     parentMenuItem: MenuItem?) -> SubmenuWindowController {
        let child = SubmenuWindowController(title: title, menuItems: menuItems,
                                            targetApp: targetApp, parentMenuItem: parentMenuItem)
        child.onWillHide = { [weak self] in
            guard let self = self else { return }
            self.childSubmenuRow = nil
            self.updateAllRowHighlights()
        }
        child.onTornOff = { [weak self, weak child] in
            guard let self = self, let child = child,
                  self.childSubmenuController === child else { return }
            self.detachedControllers.append(child)
            self.childSubmenuController = nil
            self.childSubmenuRow = nil
            self.updateAllRowHighlights()
        }
        // An action performed deep in the chain collapses back to this window.
        child.dismissChain = { [weak self] in
            self?.collapseSubmenus()
        }
        child.onPointerEntered = { [weak self] in
            guard let self = self else { return }
            if !self.childHasMouse {
                self.childHasMouse = true
                self.updateAllRowHighlights()
            }
        }
        return child
    }
}

// MARK: - NSTableViewDataSource
extension MenuWindowController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        // Add 1 for the "Info" row
        return visibleMenuItems.count + 1
    }
}

// MARK: - NSTableViewDelegate
extension MenuWindowController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellIdentifier = NSUserInterfaceItemIdentifier("MenuItemCell")

        var cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView

        if cell == nil {
            cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: rowHeight))
            cell?.identifier = cellIdentifier
            cell?.wantsLayer = true

            // Rounded selection highlight, shown/hidden by
            // updateRowHighlight(). Full row height (no gap between items).
            let backgroundView = NextMenusRendering.makeSelectionBackground(
                frame: CGRect(x: 6, y: 0, width: windowWidth - 12, height: rowHeight)
            )
            backgroundView.identifier = NSUserInterfaceItemIdentifier("BackgroundView")
            backgroundView.autoresizingMask = [.width, .height]
            backgroundView.isHidden = true
            cell?.addSubview(backgroundView)

            // Full-height label; CenteredLabel keeps the text vertically centered
            let textField = CenteredLabel(frame: NSRect(x: 18, y: 0, width: windowWidth - 56, height: rowHeight))
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

            // Trailing disclosure chevron - main menu items are all submenus
            let chevronView = NSImageView(frame: NSRect(x: windowWidth - 30, y: 0, width: 14, height: rowHeight))
            chevronView.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .bold))
            chevronView.imageScaling = .scaleNone
            chevronView.imageAlignment = .alignCenter
            chevronView.identifier = NSUserInterfaceItemIdentifier("ChevronView")
            cell?.addSubview(chevronView)
        }

        let chevronView = cell?.subviews.first {
            $0.identifier == NSUserInterfaceItemIdentifier("ChevronView")
        } as? NSImageView

        // First row is "Info" (the app menu)
        if row == 0 {
            cell?.textField?.stringValue = "Info"
            cell?.textField?.font = NSFont.systemFont(ofSize: 13)
            cell?.textField?.textColor = appMenuItem?.isEnabled ?? true ? .labelColor : .disabledControlTextColor
            cell?.textField?.isHidden = false
            chevronView?.isHidden = false
            chevronView?.contentTintColor = appMenuItem?.isEnabled ?? true ? .labelColor : .disabledControlTextColor
        } else {
            let menuItem = visibleMenuItems[row - 1]

            // Handle separators
            if menuItem.isSeparator {
                cell?.textField?.isHidden = true
                chevronView?.isHidden = true

                // Add separator line if not already added
                let separatorId = NSUserInterfaceItemIdentifier("Separator")
                if cell?.subviews.first(where: { $0.identifier == separatorId }) == nil {
                    let separator = NSBox(frame: NSRect(x: 0, y: rowHeight / 2 - 0.5, width: windowWidth, height: 1))
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
                chevronView?.isHidden = false
                chevronView?.contentTintColor = menuItem.isEnabled ? .labelColor : .disabledControlTextColor

                // Remove separator if it exists
                let separatorId = NSUserInterfaceItemIdentifier("Separator")
                cell?.subviews.first(where: { $0.identifier == separatorId })?.removeFromSuperview()
            }
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
        if row == 0 {
            return appMenuItem?.isEnabled ?? true
        } else {
            let menuItem = visibleMenuItems[row - 1]
            return menuItem.isEnabled && !menuItem.isSeparator
        }
    }

    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        // Update row background based on whether it has an open submenu
        updateRowHighlight(forRow: row)
    }

    private func updateRowHighlight(forRow row: Int) {
        guard let cellView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView else { return }

        // Only enabled, non-separator rows can be highlighted
        let hoverable = tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false

        // Highlight if this row has an open submenu, or if it's being hovered
        // while a sibling already has an open submenu or a drag is in progress
        let isHighlighted = hoverable
            && ((childSubmenuRow == row)
                || (hoveredRow == row && (childSubmenuRow != nil || isDragging)))

        let highlightView = cellView.subviews.first {
            $0.identifier == NSUserInterfaceItemIdentifier("BackgroundView")
        }
        highlightView?.isHidden = !isHighlighted
        // The open-submenu row de-emphasizes (different material, not the blue
        // selection) while the pointer is down in the child submenu.
        if let effect = highlightView as? NSVisualEffectView {
            let inChild = (childSubmenuRow == row) && childHasMouse
            effect.isEmphasized = !inChild
        }
        cellView.backgroundStyle = isHighlighted ? .emphasized : .normal
    }

    // Handle mouse up - submenu opening is handled on mouse down
    private func handleMouseUp(_ row: Int, wasDragged: Bool) {
        isDragging = false
        // A click-drag released on a menu item closes its open submenu
        if wasDragged, row >= 0, childSubmenuRow == row {
            collapseSubmenus()
        }
        // A click can also raise this window on mouse-up; keep the chain on top
        DispatchQueue.main.async { [weak self] in self?.raiseSubmenuChain() }
    }

    // Handle long press release - close menus
    private func handleMouseLongPressReleased(_ row: Int) {
        childSubmenuController?.hideWindow()
        childSubmenuController = nil
        childSubmenuRow = nil
        hoveredRow = nil
        isDragging = false
        updateAllRowHighlights()
    }

    // Execute action at row (called from child window)
    func executeActionAtRow(_ row: Int) {
        guard row >= 0 else { return }
        guard tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false else { return }

        let menuItem: MenuItem?
        if row == 0 {
            menuItem = appMenuItem
        } else {
            menuItem = menuItems[row - 1]
        }

        guard let menuItem = menuItem, let element = menuItem.element else { return }

        // Execute action
        targetApp?.activate(options: [])
        usleep(50000)
        AXUIElementPerformAction(element, kAXPressAction as CFString)
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

        // Clicking the item whose submenu is already open - close it
        if childSubmenuRow == row {
            collapseSubmenus()
            return
        }

        // Use the pre-extracted submenu tree (falls back to on-demand)
        let submenuItems = MenuExtractor.submenuItems(for: menuItem)

        // Row 0 is the app menu, shown as "Info" - its submenu uses that title
        let displayTitle = (row == 0) ? "Info" : menuItem.title

        if !submenuItems.isEmpty {
            // Reuse the existing child window if one is open, otherwise create
            // one - reusing avoids slow per-switch window/monitor setup.
            if let child = childSubmenuController {
                child.reconfigure(title: displayTitle, menuItems: submenuItems,
                                  parentMenuItem: menuItem)
                child.showWindow(rightOf: menuWindow, alignedToRow: row)
            } else {
                let child = makeChildController(title: displayTitle,
                                                menuItems: submenuItems,
                                                parentMenuItem: menuItem)
                childSubmenuController = child
                child.showWindow(rightOf: menuWindow, alignedToRow: row)
            }
            childSubmenuRow = row
            updateAllRowHighlights()
        } else {
            // No submenu - this is an action item, execute it
            targetApp?.activate(options: [])
            usleep(50000) // 50ms - let activation complete
            AXUIElementPerformAction(element, kAXPressAction as CFString)
            collapseSubmenus()
        }
    }
}
