import Cocoa
import ServiceManagement

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

    // Trailing actions appended after the menu bar items: Hide and Quit the
    // target app. Source of truth for row mapping and execution.
    private enum TrailingAction {
        case hide, quit, logOut

        var title: String {
            switch self {
            case .hide: return "Hide"
            case .quit: return "Quit"
            case .logOut: return "Log Out"
            }
        }

        var shortcutGlyph: String {
            switch self {
            case .hide: return "⌘H"
            case .quit: return "⌘Q"
            case .logOut: return "⇧⌘Q"
            }
        }
    }

    // Override hover/selection on a specific row while it flashes after a
    // click. Mirrors the SubmenuWindowController flash mechanism.
    private var flashState: (row: Int, on: Bool)?

    // Row the mouse is currently pressed on (-1 / nil = none). Used to give
    // trailing-action rows a press-only selection (no plain-hover highlight).
    private var pressedRow: Int?

    // True if the row pressed on had its submenu already open at mousedown.
    // The toggle-close fires on the matching mouseup (matching the native
    // menu bar behavior - mousedown doesn't close, mouseup does).
    private var pressedRowWasOpen: Bool = false

    // True after a click has opened a submenu and the menu is in "tracking
    // mode" - hovering siblings switches the open submenu, and hovering a
    // trailing action (Hide / Quit) highlights it and closes the submenu
    // without leaving tracking mode. Reset when the menu is dismissed
    // (action performed, toggle-close, mouseup off the menu, etc.).
    private var isMenuActive: Bool = false

    // Dock-like auto-hide state for the main menu window.
    private var hideHoverMonitor: Any?
    private var localHideHoverMonitor: Any?
    private var isHoverHidden: Bool = false
    private var normalVisibleOrigin: NSPoint?
    private let hoverHideAnimationDuration: TimeInterval = 0.16
    private let hoverHideShadowClearance: CGFloat = 32

    private var promotedAppMenuItemsCache: (version: Int, items: [MenuItem])?

    private var promotedAppMenuItems: [MenuItem] {
        guard NextMenusSettings.showServicesInMainMenu else { return [] }
        if let cache = promotedAppMenuItemsCache,
           cache.version == menuItemsVersion {
            return cache.items
        }

        let appItems = appMenuItem.map { MenuExtractor.submenuItems(for: $0) } ?? []
        let items = appItems.filter { !$0.isSeparator && $0.title == "Services" }
        promotedAppMenuItemsCache = (menuItemsVersion, items)
        return items
    }

    private var visibleTrailingActions: [TrailingAction] {
        var actions: [TrailingAction] = []
        if NextMenusSettings.showHideInMainMenu { actions.append(.hide) }
        if NextMenusSettings.showQuitInMainMenu {
            actions.append(isFinderTarget ? .logOut : .quit)
        }
        return actions
    }

    private var isFinderTarget: Bool {
        targetApp?.bundleIdentifier == "com.apple.finder"
    }

    private var firstPromotedAppMenuItemRow: Int { 1 + visibleMenuItems.count }
    private var firstTrailingActionRow: Int { firstPromotedAppMenuItemRow + promotedAppMenuItems.count }

    private func promotedAppMenuItem(at row: Int) -> MenuItem? {
        let start = firstPromotedAppMenuItemRow
        let promoted = promotedAppMenuItems
        guard row >= start, row < start + promoted.count else { return nil }
        return promoted[row - start]
    }

    private func mainMenuItem(at row: Int) -> MenuItem? {
        if row == 0 { return appMenuItem }
        if let promoted = promotedAppMenuItem(at: row) { return promoted }
        guard row > 0, row < firstPromotedAppMenuItemRow else { return nil }
        return visibleMenuItems[row - 1]
    }

    private func trailingAction(at row: Int) -> TrailingAction? {
        let start = firstTrailingActionRow
        let actions = visibleTrailingActions
        guard row >= start, row < start + actions.count else { return nil }
        return actions[row - start]
    }

    // Track window movement completion
    private var moveTimer: Timer?

    // State management for menu interactions
    private var hoveredRow: Int? // Currently highlighted row (visual only)
    private var isDragging: Bool = false // True while a click-drag is in progress
    private var asyncSubmenuOpenGeneration = 0

    // Track local event monitor for cross-window drag
    private var localDragMonitor: Any?

    // Global monitor: a click outside any of our windows (i.e. in the target
    // app) exits the click-open tracking mode.
    private var clickOutsideMonitor: Any?

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
        promotedAppMenuItemsCache = nil
    }

    init(appName: String, appMenuItem: MenuItem?, menuItems: [MenuItem], targetApp: NSRunningApplication) {
        self.appName = appName
        self.appMenuItem = appMenuItem
        self.menuItems = menuItems
        self.targetApp = targetApp

        // Calculate window height based on number of items
        // Add 1 for the "Info" row (app menu)
        let numberOfTrailingRows = (NextMenusSettings.showHideInMainMenu ? 1 : 0)
            + (NextMenusSettings.showQuitInMainMenu ? 1 : 0)
        let numberOfRows = menuItems.count + 1 + numberOfTrailingRows
        let contentHeight = CGFloat(numberOfRows) * rowHeight
        let windowHeight = contentHeight + titleBarHeight + Self.bottomMargin - 1

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

        if let window = menuWindow as? NonActivatingWindow {
            window.onRightMouseDown = { [weak self] event in
                self?.showContextMenu(with: event)
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange(_:)),
            name: NextMenusSettings.defaultsChangedNotification,
            object: nil
        )
    }

    private func setInteractionMonitoringEnabled(_ enabled: Bool) {
        if enabled {
            if localDragMonitor == nil { setupDragMonitor() }
            if clickOutsideMonitor == nil { setupClickOutsideMonitor() }
            if modifierMonitor == nil { setupModifierMonitor() }
            if NextMenusSettings.enableHiding, hideHoverMonitor == nil || localHideHoverMonitor == nil { setupHideHoverMonitor() }
        } else {
            if let monitor = localDragMonitor {
                NSEvent.removeMonitor(monitor)
                localDragMonitor = nil
            }
            if let monitor = clickOutsideMonitor {
                NSEvent.removeMonitor(monitor)
                clickOutsideMonitor = nil
            }
            if let monitor = modifierMonitor {
                NSEvent.removeMonitor(monitor)
                modifierMonitor = nil
            }
            if let monitor = hideHoverMonitor {
                NSEvent.removeMonitor(monitor)
                hideHoverMonitor = nil
            }
            if let monitor = localHideHoverMonitor {
                NSEvent.removeMonitor(monitor)
                localHideHoverMonitor = nil
            }
        }
    }

    private func setupHideHoverMonitor() {
        if hideHoverMonitor == nil {
            hideHoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
                DispatchQueue.main.async { self?.updateHoverHiding(for: NSEvent.mouseLocation) }
            }
        }
        if localHideHoverMonitor == nil {
            localHideHoverMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
                self?.updateHoverHiding(for: NSEvent.mouseLocation)
                return event
            }
        }
    }

    private func setupDragMonitor() {
        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self = self else { return event }

            let mouseLocation = NSEvent.mouseLocation

            if event.type == .leftMouseDragged,
               self.isDragging,
               !self.menuWindow.frame.contains(mouseLocation),
               self.hoveredRow != nil {
                self.hoveredRow = nil
                self.updateAllRowHighlights()
            }

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
                // Forward mouse up to child and consume it so the parent table
                // doesn't also treat the release as outside itself and collapse
                // the submenu before the child can flash/perform its action.
                childController.handleMouseUpFromParent(at: childRow)
                self.isDragging = false
                self.hoveredRow = nil
                self.updateAllRowHighlights()
                return nil
            }

            return event
        }
    }

    private func setupClickOutsideMonitor() {
        // Global monitor fires only for events delivered to *other* apps -
        // clicks on our own (non-activating) panels go through local
        // monitors instead. So any click that reaches this handler is by
        // definition outside our menu chain: collapse and exit tracking.
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self = self else { return }
            let mouseLocation = NSEvent.mouseLocation
            if self.menuWindow.frame.contains(mouseLocation)
                || (self.childSubmenuController?.containsScreenPointInChain(mouseLocation) ?? false) {
                return
            }
            if self.isMenuActive || self.childSubmenuRow != nil {
                self.collapseSubmenus()
            }
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
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = hideHoverMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localHideHoverMonitor {
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

    @objc private func settingsDidChange(_ notification: Notification) {
        if !NextMenusSettings.enableHiding {
            disableHoverHiding()
        }
        invalidateVisibleMenuItemsCache()
        collapseSubmenus()
        tableView.reloadData()
        resizeWindowToFitContent()
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

        tableView.onRightMouseDown = { [weak self] event in
            self?.showContextMenu(with: event)
        }

        // Add table view to scroll view
        scrollView.documentView = tableView

        // Add scroll view to window
        contentView.addSubview(scrollView)
    }

    private func showContextMenu(with event: NSEvent) {
        collapseSubmenus()

        let menu = NSMenu()
        menu.addItem(withTitle: "Reset Position", action: #selector(resetPositionFromContextMenu(_:)), keyEquivalent: "").target = self

        let insetItem = menu.addItem(withTitle: "Inset from Top Left", action: #selector(toggleTopLeftInset(_:)), keyEquivalent: "")
        insetItem.target = self
        insetItem.state = NextMenusSettings.useZeroTopLeftInset ? .off : .on

        let hidingItem = menu.addItem(withTitle: "Enable Hiding", action: #selector(toggleEnableHiding(_:)), keyEquivalent: "")
        hidingItem.target = self
        hidingItem.state = NextMenusSettings.enableHiding ? .on : .off

        menu.addItem(.separator())

        let servicesItem = menu.addItem(withTitle: "Show Services in Main Menu", action: #selector(toggleShowServices(_:)), keyEquivalent: "")
        servicesItem.target = self
        servicesItem.state = NextMenusSettings.showServicesInMainMenu ? .on : .off

        let hideItem = menu.addItem(withTitle: "Show Hide in Main Menu", action: #selector(toggleShowHide(_:)), keyEquivalent: "")
        hideItem.target = self
        hideItem.state = NextMenusSettings.showHideInMainMenu ? .on : .off

        let quitItem = menu.addItem(withTitle: "Show Quit in Main Menu", action: #selector(toggleShowQuit(_:)), keyEquivalent: "")
        quitItem.target = self
        quitItem.state = NextMenusSettings.showQuitInMainMenu ? .on : .off

        menu.addItem(.separator())

        let openAtLoginItem = menu.addItem(withTitle: "Open at Login", action: #selector(toggleOpenAtLogin(_:)), keyEquivalent: "")
        openAtLoginItem.target = self
        openAtLoginItem.state = isOpenAtLoginEnabled ? .on : .off

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit NeXTMenus", action: #selector(quitNextMenus(_:)), keyEquivalent: "").target = self

        NSMenu.popUpContextMenu(menu, with: event, for: tableView)
    }

    @objc private func resetPositionFromContextMenu(_ sender: NSMenuItem) {
        resetPosition()
    }

    @objc private func toggleTopLeftInset(_ sender: NSMenuItem) {
        NextMenusSettings.useZeroTopLeftInset.toggle()
        resetPosition()
    }

    @objc private func toggleShowServices(_ sender: NSMenuItem) {
        NextMenusSettings.showServicesInMainMenu.toggle()
    }

    @objc private func toggleEnableHiding(_ sender: NSMenuItem) {
        NextMenusSettings.enableHiding.toggle()
        if NextMenusSettings.enableHiding {
            normalVisibleOrigin = visibleOriginForCurrentScreen()
            showWindow()
            hideForHover()
        } else {
            disableHoverHiding()
        }
    }

    @objc private func toggleShowHide(_ sender: NSMenuItem) {
        NextMenusSettings.showHideInMainMenu.toggle()
    }

    @objc private func toggleShowQuit(_ sender: NSMenuItem) {
        NextMenusSettings.showQuitInMainMenu.toggle()
    }

    private var isOpenAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleOpenAtLogin(_ sender: NSMenuItem) {
        do {
            if isOpenAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
            NSLog("Failed to update Open at Login: \(error.localizedDescription)")
        }
    }

    @objc private func quitNextMenus(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
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
        // Once a submenu is open (or the menu is in click-open tracking mode),
        // hovering a sibling switches the open submenu. Tracking mode persists
        // through trailing-action hovers that close the current submenu, so
        // hovering a submenu item afterwards still opens it.
        if rowChanged, childSubmenuRow != nil || isMenuActive {
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
        pressedRow = row >= 0 ? row : nil
        pressedRowWasOpen = false
        guard row >= 0 else { return }
        guard tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false else { return }

        // Trailing actions act on mouse-up; the press shows selection feedback
        if trailingAction(at: row) != nil {
            updateAllRowHighlights()
            return
        }

        // If this row's submenu is already open, defer the toggle-close to
        // mouseup (matches native menu bar - the menu doesn't close on
        // mousedown). Mark it so the mouseup handler knows to toggle.
        if childSubmenuRow == row {
            pressedRowWasOpen = true
            updateAllRowHighlights()
            return
        }

        guard let menuItem = mainMenuItem(at: row), !menuItem.isSeparator else { return }
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

        // Keep drag-hover selection instant: extract/open the submenu away
        // from the mouse-tracking call stack, then show it only if this row is
        // still the active drag hover when extraction finishes.
        openSubmenuFromDragAsync(forRow: row)
    }

    // Switches the open submenu to the hovered row. A row of -1 means the
    // pointer is off the menu items - the submenu is left open only if the
    // pointer is over the child window itself.
    private func updateOpenSubmenu(forHoveredRow row: Int) {
        if row < 0 {
            // Off the menu items - leave any open submenu alone. The mouse
            // routinely crosses deadspace while moving between parent and
            // child windows (especially with short submenus), so we don't
            // close here. Closing happens deliberately on sibling-hover or
            // mouse-up.
            return
        }
        if childSubmenuRow == row { return }
        guard tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false else { return }
        // Trailing actions don't have submenus; hovering one (during a drag
        // or with a submenu open) collapses whatever is open. Stay in
        // tracking mode (isMenuActive) so a follow-up hover on a submenu
        // sibling still opens it.
        if trailingAction(at: row) != nil {
            if childSubmenuRow != nil {
                collapseSubmenus(endsTracking: false)
            }
            return
        }
        // While click-dragging with a submenu already open, hovering a sibling
        // closes the open submenu rather than switching - the drag is
        // committed to the row that started it.
        if isDragging, childSubmenuRow != nil {
            collapseSubmenus()
            return
        }
        guard let menuItem = mainMenuItem(at: row), !menuItem.isSeparator else { return }
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
        setInteractionMonitoringEnabled(true)
        if NextMenusSettings.enableHiding {
            normalVisibleOrigin = normalVisibleOrigin ?? visibleOriginForCurrentScreen()
            if isHoverHidden { hideForHover() }
        }
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
        let height = contentH + titleBarHeight + Self.bottomMargin - 1
        var frame = menuWindow.frame
        frame.origin.y += frame.size.height - height  // keep the top edge fixed
        frame.size.height = height
        menuWindow.setFrame(frame, display: true)
        // Pin the table to its content height. As a scroll-view documentView
        // it doesn't auto-shrink when the clip does, so a stale taller frame
        // would let the scroll view scroll past the rows.
        tableView.frame.size.height = contentH
    }

    func resetPosition(on targetScreen: NSScreen? = nil) {
        guard let screen = targetScreen ?? screenContainingMouse() ?? NSScreen.main else {
            return
        }

        let origin = visibleOrigin(on: screen)
        normalVisibleOrigin = origin
        isHoverHidden = false
        menuWindow.setFrameOrigin(origin)

        if NextMenusSettings.enableHiding {
            hideForHover(animated: false)
        }
    }

    private func visibleOriginForCurrentScreen() -> NSPoint? {
        guard let screen = screenContainingMouse() ?? NSScreen.main else {
            return nil
        }
        return visibleOrigin(on: screen)
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
    }

    private func visibleOrigin(on screen: NSScreen) -> NSPoint {
        let windowHeight = menuWindow.frame.height
        let inset = NextMenusSettings.topLeftInset
        return NSPoint(
            x: screen.frame.origin.x + inset,
            y: screen.frame.maxY - windowHeight - inset
        )
    }

    private func disableHoverHiding() {
        if let monitor = hideHoverMonitor {
            NSEvent.removeMonitor(monitor)
            hideHoverMonitor = nil
        }
        if let monitor = localHideHoverMonitor {
            NSEvent.removeMonitor(monitor)
            localHideHoverMonitor = nil
        }
        isHoverHidden = false
        if let origin = normalVisibleOrigin ?? visibleOriginForCurrentScreen() {
            menuWindow.setFrameOrigin(origin)
        }
    }

    private func hideForHover(animated: Bool = true) {
        guard NextMenusSettings.enableHiding else { return }
        let visibleOrigin = normalVisibleOrigin ?? menuWindow.frame.origin
        normalVisibleOrigin = visibleOrigin
        let screenLeftEdge = visibleOrigin.x - NextMenusSettings.topLeftInset
        let hiddenOrigin = NSPoint(x: screenLeftEdge - menuWindow.frame.width - hoverHideShadowClearance, y: visibleOrigin.y)
        setHoverFrameOrigin(hiddenOrigin, animated: animated)
        isHoverHidden = true
    }

    private func showForHover(animated: Bool = true) {
        guard let origin = normalVisibleOrigin ?? visibleOriginForCurrentScreen() else { return }
        normalVisibleOrigin = origin
        setHoverFrameOrigin(origin, animated: animated)
        isHoverHidden = false
    }

    private func setHoverFrameOrigin(_ origin: NSPoint, animated: Bool) {
        guard animated else {
            menuWindow.setFrameOrigin(origin)
            return
        }

        var frame = menuWindow.frame
        frame.origin = origin
        NSAnimationContext.runAnimationGroup { context in
            context.duration = hoverHideAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            menuWindow.animator().setFrame(frame, display: true)
        }
    }

    private var shouldDeferHoverHide: Bool {
        pressedRow != nil || isDragging || isMenuActive || childSubmenuRow != nil
    }

    private func updateHoverHiding(for mouseLocation: NSPoint) {
        guard NextMenusSettings.enableHiding, menuWindow.isVisible else { return }
        let frame = menuWindow.frame

        if isHoverHidden {
            guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
            let visibleFrame = NSRect(
                origin: normalVisibleOrigin ?? visibleOrigin(on: screen),
                size: frame.size
            )
            if mouseLocation.x <= screen.frame.minX + 1,
               mouseLocation.y >= visibleFrame.minY,
               mouseLocation.y <= visibleFrame.maxY {
                showForHover()
            }
            return
        }

        guard !shouldDeferHoverHide else { return }
        if mouseLocation.x > frame.maxX || mouseLocation.y < frame.minY {
            // Do not immediately re-hide while the pointer is still on the
            // left-edge reveal strip; this prevents edge jitter/flicker.
            if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main,
               mouseLocation.x <= screen.frame.minX + 1,
               mouseLocation.y >= frame.minY,
               mouseLocation.y <= frame.maxY {
                return
            }
            collapseSubmenus()
            hideForHover()
        }
    }

    func hideWindow() {
        // Hide child submenu first
        childSubmenuController?.hideWindow()
        childSubmenuController = nil
        childSubmenuRow = nil
        hoveredRow = nil

        menuWindow.orderOut(nil)
        setInteractionMonitoringEnabled(false)
    }

    // Collapses the whole submenu chain back to this main menu window.
    // `endsTracking` clears the click-open tracking state; pass false when
    // closing as a hover side-effect (e.g. hovering a trailing action while
    // a submenu is open) so subsequent hovers can still open submenus.
    func collapseSubmenus(endsTracking: Bool = true) {
        asyncSubmenuOpenGeneration += 1
        childSubmenuController?.hideWindow()
        childSubmenuController = nil
        childSubmenuRow = nil
        hoveredRow = nil
        isDragging = false
        pressedRow = nil
        pressedRowWasOpen = false
        childHasMouse = false
        if endsTracking { isMenuActive = false }
        updateAllRowHighlights()
    }

    private func dismissAfterAction() {
        collapseSubmenus()
        if NextMenusSettings.enableHiding {
            hideForHover()
        }
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
            self.hoveredRow = nil
            self.isDragging = false
            self.pressedRow = nil
            self.pressedRowWasOpen = false
            self.childHasMouse = false
            self.isMenuActive = false
            self.asyncSubmenuOpenGeneration += 1
            self.updateAllRowHighlights()
        }
        // An action performed deep in the attached chain dismisses/hides the main menu.
        child.dismissChain = { [weak self] in
            self?.dismissAfterAction()
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
        // 1 for "Info" + the menu bar items + promoted app-menu items + visible trailing actions
        return 1 + visibleMenuItems.count + promotedAppMenuItems.count + visibleTrailingActions.count
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
            chevronView.imageAlignment = .alignRight
            chevronView.identifier = NSUserInterfaceItemIdentifier("ChevronView")
            cell?.addSubview(chevronView)

            // Right-aligned shortcut (shown for the trailing Hide/Quit rows).
            // Rendered as fixed-width cells via ShortcutView; sized per
            // configure() since the cell count varies.
            let shortcutField = ShortcutView(frame: NSRect(x: windowWidth - 16, y: 0, width: 0, height: rowHeight))
            shortcutField.identifier = NSUserInterfaceItemIdentifier("ShortcutField")
            shortcutField.isHidden = true
            cell?.addSubview(shortcutField)
        }

        let chevronView = cell?.subviews.first {
            $0.identifier == NSUserInterfaceItemIdentifier("ChevronView")
        } as? NSImageView
        let shortcutField = cell?.subviews.first {
            $0.identifier == NSUserInterfaceItemIdentifier("ShortcutField")
        } as? ShortcutView

        // Trailing actions (Hide / Quit the target app) - no chevron, with
        // the keyboard shortcut on the right
        if let action = trailingAction(at: row) {
            cell?.textField?.isHidden = false
            cell?.textField?.stringValue = action.title
            cell?.textField?.font = NSFont.systemFont(ofSize: 13)
            cell?.textField?.textColor = .labelColor
            chevronView?.isHidden = true
            // Same fixed-cell rendering as SubmenuWindowController.
            shortcutField?.isHidden = false
            let key = action.shortcutGlyph
            let w = ShortcutView.intrinsicWidth(for: key)
            let trailingX = windowWidth - 16
            shortcutField?.frame = NSRect(x: trailingX - w, y: 0, width: w, height: rowHeight)
            shortcutField?.configure(with: key)
            let separatorId = NSUserInterfaceItemIdentifier("Separator")
            cell?.subviews.first(where: { $0.identifier == separatorId })?.removeFromSuperview()
            return cell
        }

        // Non-trailing rows don't show the shortcut field
        shortcutField?.isHidden = true

        // First row is "Info" (the app menu)
        if row == 0 {
            cell?.textField?.stringValue = "Info"
            cell?.textField?.font = NSFont.systemFont(ofSize: 13)
            cell?.textField?.textColor = appMenuItem?.isEnabled ?? true ? .labelColor : .disabledControlTextColor
            cell?.textField?.isHidden = false
            chevronView?.isHidden = false
            chevronView?.contentTintColor = appMenuItem?.isEnabled ?? true ? .labelColor : .disabledControlTextColor
        } else if let menuItem = mainMenuItem(at: row) {

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
        }
        if trailingAction(at: row) != nil {
            return true
        }
        guard let menuItem = mainMenuItem(at: row) else { return false }
        return menuItem.isEnabled && !menuItem.isSeparator
    }

    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        // Update row background based on whether it has an open submenu
        updateRowHighlight(forRow: row)
    }

    private func updateRowHighlight(forRow row: Int) {
        guard let cellView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView else { return }

        // Flash overrides everything else (used by trailing-action click)
        let isHighlighted: Bool
        if let flashState = flashState, flashState.row == row {
            isHighlighted = flashState.on
        } else {
            // Only enabled, non-separator rows can be highlighted
            let hoverable = tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false
            if isDragging {
                // During click-drag over main-menu rows, only the hovered row
                // is selected. Keep the open-submenu row grey only after the
                // pointer has left main rows, e.g. while dragging in the child.
                let pointerIsOffMainRows = (hoveredRow ?? -1) < 0
                isHighlighted = hoverable
                    && (hoveredRow == row || (pointerIsOffMainRows && childSubmenuRow == row))
            } else if trailingAction(at: row) != nil {
                // Trailing actions (Hide / Quit) don't highlight on plain
                // hover - only when pressed or while the menu is in
                // click-open tracking mode.
                isHighlighted = hoverable
                    && hoveredRow == row
                    && (pressedRow == row || isMenuActive)
            } else {
                isHighlighted = hoverable
                    && ((childSubmenuRow == row)
                        || (hoveredRow == row && childSubmenuRow != nil))
            }
        }

        let highlightView = cellView.subviews.first {
            $0.identifier == NSUserInterfaceItemIdentifier("BackgroundView")
        }
        highlightView?.isHidden = !isHighlighted
        // The open-submenu row de-emphasizes (different material, not the blue
        // selection) while the pointer is down in the child submenu.
        if let effect = highlightView as? NSVisualEffectView {
            let pointerIsOffMainRows = (hoveredRow ?? -1) < 0
            let deEmphasizeOpenSubmenu = (childSubmenuRow == row)
                && (childHasMouse || (isDragging && pointerIsOffMainRows))
            effect.isEmphasized = !deEmphasizeOpenSubmenu
        }
        cellView.backgroundStyle = isHighlighted ? .emphasized : .normal
        // ShortcutView's text labels aren't covered by NSTableCellView's
        // textField propagation, so push the emphasis state to them too.
        let shortcutField = cellView.subviews.first {
            $0.identifier == NSUserInterfaceItemIdentifier("ShortcutField")
        } as? ShortcutView
        shortcutField?.setEmphasized(isHighlighted)
    }

    // Handle mouse up - submenu opening is handled on mouse down
    private func handleMouseUp(_ row: Int, wasDragged: Bool) {
        let wasPressedRow = pressedRow
        let wasPressedRowWasOpen = pressedRowWasOpen
        isDragging = false
        pressedRow = nil
        pressedRowWasOpen = false
        // Trailing actions (Hide / Quit) fire on release, with a flash
        if let action = trailingAction(at: row) {
            performTrailingAction(action, at: row)
            return
        }
        // Released off any menu item or outside the menu window - clear hover
        // and collapse any open submenu.
        if row < 0 {
            hoveredRow = nil
            if childSubmenuRow != nil {
                collapseSubmenus()
            } else {
                isMenuActive = false
                updateAllRowHighlights()
            }
            return
        }
        if !(tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false) {
            hoveredRow = nil
            collapseSubmenus()
            return
        }
        // Toggle-close: a click (no drag) on a row that was already showing
        // its submenu at mousedown closes the chain on release - matches the
        // native menu bar behavior of mouseup, not mousedown, doing the work.
        if !wasDragged, wasPressedRowWasOpen, wasPressedRow == row {
            collapseSubmenus()
            return
        }
        // Click-drag-and-release on a main menu item triggers it: submenu
        // parents stay open in tracking mode (don't close the chain), and
        // the trailing-action branch above already handles Hide / Quit.
        // A click can also raise this window on mouse-up; keep the chain on top
        DispatchQueue.main.async { [weak self] in self?.raiseSubmenuChain() }
    }

    private func performTrailingAction(_ action: TrailingAction, at row: Int) {
        collapseSubmenus()
        flashRow(row) { [weak self] in
            guard let self = self else { return }
            switch action {
            case .hide:
                self.targetApp?.hide()
            case .quit:
                self.targetApp?.terminate()
            case .logOut:
                self.performLogOutShortcut()
            }
        }
    }

    private func performLogOutShortcut() {
        // Finder doesn't expose this as a normal app-menu item; the row exists
        // to mirror NeXT's menu. Send loginwindow the standard logout Apple
        // event directly, which avoids relying on Finder/System Events menus.
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.loginwindow")

        let event = NSAppleEventDescriptor(
            eventClass: fourCharCode("aevt"),
            eventID: fourCharCode("logo"),
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )

        _ = try? event.sendEvent(options: .defaultOptions, timeout: 5)
    }

    private func fourCharCode(_ string: String) -> FourCharCode {
        string.utf8.reduce(0) { ($0 << 8) + FourCharCode($1) }
    }

    // Briefly flash a row's highlight off then on before running completion.
    private func flashRow(_ row: Int, completion: @escaping () -> Void) {
        var step = 0
        let totalSteps = 2
        flashState = (row, false)
        updateRowHighlight(forRow: row)
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            step += 1
            self.flashState = (row, step % 2 != 0)
            self.updateRowHighlight(forRow: row)
            if step >= totalSteps {
                timer.invalidate()
                self.flashState = nil
                self.updateRowHighlight(forRow: row)
                completion()
            }
        }
    }

    // Handle long press release - close menus
    private func handleMouseLongPressReleased(_ row: Int) {
        // A slow click is still a click - route through the normal mouseup
        // path so trailing actions (Hide / Quit) fire and submenu open/close
        // state stays correct.
        handleMouseUp(row, wasDragged: false)
    }

    // Execute action at row (called from child window)
    func executeActionAtRow(_ row: Int) {
        guard row >= 0 else { return }
        guard tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false else { return }

        guard let menuItem = mainMenuItem(at: row), let element = menuItem.element else { return }

        // Execute action
        targetApp?.activate(options: [])
        usleep(50000)
        AXUIElementPerformAction(element, kAXPressAction as CFString)
        dismissAfterAction()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0 else { return }

        // Deselect immediately for button-like behavior
        tableView.deselectRow(selectedRow)

        // Get the menu item
        guard let menuItem = mainMenuItem(at: selectedRow) else { return }

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
        showSubmenu(for: menuItem, at: row, submenuItems: submenuItems, fallbackElement: element)
    }

    private func openSubmenuFromDragAsync(forRow row: Int) {
        asyncSubmenuOpenGeneration += 1
        let generation = asyncSubmenuOpenGeneration

        guard row >= 0 else { return }

        guard childSubmenuRow != row,
              tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false,
              let menuItem = mainMenuItem(at: row),
              !menuItem.isSeparator,
              menuItem.hasSubmenu else {
            if let childSubmenuRow, childSubmenuRow != row {
                collapseSubmenus(endsTracking: false)
                hoveredRow = row
                isDragging = true
                updateAllRowHighlights()
            }
            return
        }

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let submenuItems = MenuExtractor.submenuItems(for: menuItem)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                guard self.asyncSubmenuOpenGeneration == generation else { return }
                guard self.isDragging, self.hoveredRow == row else { return }
                self.showSubmenu(for: menuItem, at: row, submenuItems: submenuItems, fallbackElement: nil)
            }
        }
    }

    private func showSubmenu(for menuItem: MenuItem, at row: Int, submenuItems: [MenuItem], fallbackElement: AXUIElement?) {
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
            isMenuActive = true
            updateAllRowHighlights()
        } else if let element = fallbackElement {
            // No submenu - this is an action item, execute it
            targetApp?.activate(options: [])
            usleep(50000) // 50ms - let activation complete
            AXUIElementPerformAction(element, kAXPressAction as CFString)
            dismissAfterAction()
        }
    }
}
