import Cocoa

class SubmenuWindowController: NSWindowController {
    private var submenuWindow: NSWindow!
    private var tableView: HoverTableView!
    private var menuItems: [MenuItem] = []
    private var title: String = ""
    private var targetApp: NSRunningApplication?
    private var parentMenuItem: MenuItem? // Track the parent menu item
    private let rowHeight: CGFloat = 24
    private let separatorRowHeight: CGFloat = 12
    private let titleBarHeight: CGFloat = 28
    // Small breathing room below the last row so it isn't flush with the edge
    private static let bottomMargin: CGFloat = 8

    // Submenu windows size their width to their content (see computeContentWidth)
    private var windowWidth: CGFloat = 180

    // Cell layout constants
    private static let titleX: CGFloat = 26          // title left edge
    private static let titleTrailingGap: CGFloat = 8 // gap before shortcut/chevron
    private static let trailingMargin: CGFloat = 16  // right inset
    private static let minWindowWidth: CGFloat = 180
    private static let maxWindowWidth: CGFloat = 640

    // Faint, appearance-adaptive separator line. `separatorColor` is too dark
    // on the translucent menu material; tune the alpha to taste.
    private static let separatorLineColor = NSColor(name: "MenuSeparator") { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return (isDark ? NSColor.white : NSColor.black).withAlphaComponent(0.09)
    }

    // Track window state
    private var isTornOff: Bool = false
    private var userClosed: Bool = false  // close button used - stays closed
    private var initialWindowFrame: NSRect = .zero
    private var isProgrammaticMove: Bool = false
    private var moveDetectionTimer: Timer?

    // Track child submenu window
    private var childSubmenuController: SubmenuWindowController?
    private var childSubmenuRow: Int?
    private var childMoveTimer: Timer?

    // Modifier key tracking
    private var currentModifierFlags: NSEvent.ModifierFlags = []
    private var modifierMonitor: Any?

    // Computed property to get visible menu items based on current modifiers
    private var visibleMenuItems: [MenuItem] {
        let hasOption = currentModifierFlags.contains(.option)
        let hasShift = currentModifierFlags.contains(.shift)
        let hasControl = currentModifierFlags.contains(.control)

        // Filter out alternate items unless their required modifiers are pressed
        let filtered = menuItems.filter { item in
            // Always show separators
            if item.isSeparator {
                return true
            }

            // If it's marked as alternate
            if item.isAlternate {
                return hasOption || hasShift || hasControl
            }

            // Regular items - hide when modifiers are pressed if there's an alternate
            // Check if next item is an alternate of this one
            if let index = menuItems.firstIndex(where: { $0.element === item.element }),
               index + 1 < menuItems.count {
                let nextItem = menuItems[index + 1]
                if nextItem.isAlternate && !nextItem.isSeparator {
                    // This has an alternate, hide when modifiers pressed
                    return !hasOption && !hasShift && !hasControl
                }
            }

            // Regular items without alternates - always show
            return true
        }

        // Collapse runs of separators into one, and drop leading/trailing ones
        var result: [MenuItem] = []
        for item in filtered {
            if item.isSeparator && (result.last?.isSeparator ?? true) {
                continue
            }
            result.append(item)
        }
        if result.last?.isSeparator == true {
            result.removeLast()
        }
        return result
    }

    // State management for menu interactions
    private var hoveredRow: Int? // Currently highlighted row (visual only)
    private var isDragging: Bool = false // True while a click-drag is in progress

    // While an action row is flashing, this overrides hover/submenu highlight
    // for that row so the blink can't be stomped by stray hover events.
    private var flashState: (row: Int, on: Bool)?

    // Track global click monitor
    private var globalClickMonitor: Any?

    // Track local event monitor for cross-window drag
    private var localDragMonitor: Any?

    // Callback when window is about to hide
    var onWillHide: (() -> Void)?

    // Called when the user tears this window off, so the parent can release
    // its reference and create a fresh child for further navigation.
    var onTornOff: (() -> Void)?

    // Walks up the menu chain to collapse submenus after an action is
    // performed. The first torn-off ancestor (or the main menu) stops it.
    var dismissChain: (() -> Void)?

    // Called when the pointer is in this window, so an ancestor can de-emphasize
    // its open-submenu row while the pointer is deeper in the chain.
    var onPointerEntered: (() -> Void)?
    private var childHasMouse = false

    // Submenu windows the user has torn off; retained so they stay on screen.
    private var detachedControllers: [SubmenuWindowController] = []

    // Exposed so the parent can decide whether to keep this window attached.
    var isDetached: Bool { isTornOff }

    init(title: String, menuItems: [MenuItem], targetApp: NSRunningApplication?, parentMenuItem: MenuItem? = nil) {
        self.title = title
        self.menuItems = menuItems
        self.targetApp = targetApp
        self.parentMenuItem = parentMenuItem
        self.windowWidth = Self.computeContentWidth(for: menuItems)

        // Calculate window height based on number of items, using the shorter
        // row height for separators
        let separatorCount = menuItems.filter { $0.isSeparator }.count
        let contentHeight = CGFloat(menuItems.count - separatorCount) * rowHeight
            + CGFloat(separatorCount) * separatorRowHeight
        let windowHeight = contentHeight + titleBarHeight + Self.bottomMargin

        // Create window with initial frame (will be positioned when shown)
        let window = NonActivatingWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        self.submenuWindow = window
        window.title = title
        setupWindow()
        setupTableView()
        setupModifierMonitor()

        // Size the window precisely to the table's content geometry
        tableView.reloadData()
        resizeWindowToFitContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWindow() {
        // Hide traffic lights initially (will show close button when torn off)
        submenuWindow.standardWindowButton(.closeButton)?.isHidden = true
        submenuWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
        submenuWindow.standardWindowButton(.zoomButton)?.isHidden = true

        // Float above all application windows, like a real menu
        submenuWindow.level = .popUpMenu
        submenuWindow.isMovableByWindowBackground = true
        submenuWindow.styleMask.insert(.fullSizeContentView)

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

        // Track the close button so a closed torn-off window stays closed
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
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

        // A torn-off window is only visible while its target app is frontmost
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // Set up local event monitor for mouse drags to handle cross-window hovering
        setupDragMonitor()
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

    private func setupGlobalClickMonitor() {
        // Monitor global mouse clicks
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, !self.isTornOff else { return }

            // Get click location
            let clickLocation = event.locationInWindow

            // Check if click is outside this window
            if let screenClickLocation = NSEvent.mouseLocation as CGPoint?,
               !self.submenuWindow.frame.contains(screenClickLocation) {
                // Click was outside - clear highlights and close the submenu
                self.childSubmenuController?.hideWindow()
                self.childSubmenuController = nil
                self.childSubmenuRow = nil

                // Update highlights before hiding
                for i in 0..<self.tableView.numberOfRows {
                    self.updateRowHighlight(forRow: i)
                }

                self.hideWindow()
            }
        }
    }

    @objc private func applicationDidResignActive(_ notification: Notification) {
        // Only close if not torn off
        if !isTornOff {
            // Clear highlights before hiding
            childSubmenuController?.hideWindow()
            childSubmenuController = nil
            childSubmenuRow = nil

            // Update highlights
            for i in 0..<tableView.numberOfRows {
                updateRowHighlight(forRow: i)
            }

            hideWindow()
        }
    }

    // Keep a torn-off window visible only while its target app is frontmost.
    @objc private func activeApplicationChanged(_ notification: Notification) {
        guard isTornOff, !userClosed else { return }
        let frontPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if frontPid == targetApp?.processIdentifier {
            submenuWindow.orderFrontRegardless()
        } else {
            submenuWindow.orderOut(nil)
        }
    }

    // The close button was used - don't resurrect this window on app switch,
    // and close any submenus opened from it.
    @objc private func windowWillClose(_ notification: Notification) {
        userClosed = true
        childSubmenuController?.submenuWindow.close()
        childSubmenuController = nil
        childSubmenuRow = nil
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

    // Called by parent window when modifiers change
    func updateModifierFlags(_ flags: NSEvent.ModifierFlags) {
        currentModifierFlags = flags

        // Re-extract submenu items when modifiers change
        // This is necessary because macOS provides different items based on modifiers
        if let parentMenuItem = getParentMenuItem(), let element = parentMenuItem.element {
            let newSubmenuItems = MenuExtractor.extractSubmenuItemsOnDemand(from: element)
            if !newSubmenuItems.isEmpty {
                self.menuItems = newSubmenuItems
            }
        }

        tableView.reloadData()
        resizeWindowToFitContent()

        // Propagate to child if exists
        childSubmenuController?.updateModifierFlags(flags)
    }

    // Helper to get the parent menu item that opened this submenu
    private func getParentMenuItem() -> MenuItem? {
        return parentMenuItem
    }

    deinit {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localDragMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = modifierMonitor {
            NSEvent.removeMonitor(monitor)
        }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
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
                        // Hover no longer selects once torn off - clear any
                        // stale highlight immediately
                        self.updateAllRowHighlights()
                        // Let the parent release this now-independent window
                        self.onTornOff?()
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
        scrollView.hasVerticalScroller = true
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

        // Add table view to scroll view
        scrollView.documentView = tableView

        // Add scroll view to window
        contentView.addSubview(scrollView)
    }

    // MARK: - Mouse Event Handlers

    // Handle mouse hover (no button pressed) - visual highlight only
    private func handleMouseMoved(_ row: Int) {
        pointerEnteredSelf()
        let rowChanged = hoveredRow != row
        if rowChanged || isDragging {
            isDragging = false
            hoveredRow = row
            updateAllRowHighlights()
        }
        if rowChanged {
            if isTornOff {
                // Torn-off: once a submenu is open, hovering another submenu
                // item switches to it. Hovering a non-submenu item does
                // nothing - the open submenu stays and leaf rows don't react.
                if childSubmenuRow != nil, isSubmenuRow(row) {
                    updateOpenSubmenu(forHoveredRow: row)
                }
            } else {
                // Attached to the chain: plain hover opens/switches freely.
                updateOpenSubmenu(forHoveredRow: row)
            }
        }
    }

    // True if the row is an enabled item that has a submenu.
    private func isSubmenuRow(_ row: Int) -> Bool {
        guard row >= 0, row < visibleMenuItems.count else { return false }
        let item = visibleMenuItems[row]
        return item.hasSubmenu && !item.isSeparator && item.isEnabled
    }

    // The pointer is in this window: clear the "child has the pointer" flag
    // (re-emphasizing our open-submenu row) and notify ancestors so theirs
    // de-emphasize.
    private func pointerEnteredSelf() {
        if childHasMouse {
            childHasMouse = false
            updateAllRowHighlights()
        }
        onPointerEntered?()
    }

    // Handle mouse down - open the submenu immediately for items that have one
    private func handleMouseDown(_ row: Int) {
        // A click raises this window above its open submenu; re-assert the
        // chain on top afterwards so the submenu stays focused/visible.
        defer {
            DispatchQueue.main.async { [weak self] in self?.raiseSubmenuChain() }
        }
        guard row >= 0 && row < visibleMenuItems.count else { return }
        guard tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false else { return }

        // Open (or toggle) the submenu on press; leaf items act on mouse up
        if visibleMenuItems[row].hasSubmenu {
            handleMouseClickedRow(row)
        }
    }

    // Re-orders the open submenu chain above this window; the deepest one
    // becomes key. Called after a click, which would otherwise raise this
    // window on top of its own submenu.
    func raiseSubmenuChain() {
        childSubmenuController?.bringChainToFront()
    }

    // Orders this window and its descendants to the front (no makeKey, which
    // would flicker focus).
    func bringChainToFront() {
        submenuWindow.orderFront(nil)
        childSubmenuController?.bringChainToFront()
    }

    // Handle mouse drag (button held) - open menus while dragging
    private func handleMouseDragged(_ row: Int) {
        // Only count the pointer as "in this window" when it's over a row;
        // during a drag this still fires (mouse capture) when the pointer has
        // moved into a child submenu, where row is -1.
        if row >= 0 { pointerEnteredSelf() }
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

    // Opens the hovered row's submenu if it has one, otherwise collapses any
    // open submenu. A row of -1 means the pointer is off this menu's rows -
    // it's left open only if the pointer is over the child window itself.
    private func updateOpenSubmenu(forHoveredRow row: Int) {
        if row < 0 {
            // Dragging off the menu items: close the submenu unless the
            // pointer is over the child window.
            if isDragging, childSubmenuRow != nil,
               !(childSubmenuController?.window?.frame.contains(NSEvent.mouseLocation) ?? false) {
                closeSubmenu()
                updateAllRowHighlights()
            }
            return
        }
        if childSubmenuRow == row { return }

        if tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false,
           row < visibleMenuItems.count {
            let menuItem = visibleMenuItems[row]
            if !menuItem.isSeparator, menuItem.hasSubmenu {
                presentSubmenu(for: menuItem, at: row)
                return
            }
        }

        // Hovered a leaf / separator / disabled row - collapse any open submenu
        if childSubmenuRow != nil {
            closeSubmenu()
            updateAllRowHighlights()
        }
    }

    // Handle drag from parent window
    func handleDragFromParent(at row: Int) {
        handleMouseDragged(row)
    }

    // Handle mouse up from parent window
    func handleMouseUpFromParent(at row: Int) {
        handleMouseUp(row, wasDragged: true)
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

    private func closeSubmenu() {
        childSubmenuController?.hideWindow(animated: false)
        childSubmenuController = nil
        childSubmenuRow = nil
    }

    // Maps a filled mark character (as macOS reports it) to an outline glyph.
    private static func outlineMark(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespaces) {
        case "✔", "✅", "☑", "✓": return "✓"          // checkmark (a stroke glyph)
        case "◆", "♦", "⬥", "◈", "🔷", "🔹": return "◇" // filled diamond -> outline
        case "●", "•", "⦁", "▪", "■": return "◦"        // filled bullet -> outline
        default: return raw
        }
    }

    // Total height of all rows, read from the table's actual layout geometry
    // rather than recomputed from row counts.
    private func tableContentHeight() -> CGFloat {
        let count = tableView.numberOfRows
        guard count > 0 else { return 0 }
        return tableView.rect(ofRow: count - 1).maxY
    }

    // Width occupied by the title text, with a small safety margin.
    private static func titleWidth(for title: String) -> CGFloat {
        let w = (title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 13)
        ]).width
        return ceil(w) + 2
    }

    // Width occupied by the keyboard-shortcut text, with a small safety margin.
    // Used for both window sizing and cell layout so they can't diverge.
    private static func shortcutWidth(for key: String) -> CGFloat {
        guard !key.isEmpty else { return 0 }
        let w = NSAttributedString(string: key, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .kern: 2.0
        ]).size().width
        return ceil(w) + 2
    }

    // Window width that fits the widest item (title + shortcut/chevron),
    // clamped between minWindowWidth and maxWindowWidth. Beyond the max,
    // titles truncate.
    private static func computeContentWidth(for items: [MenuItem]) -> CGFloat {
        var maxWidth: CGFloat = 0
        for item in items where !item.isSeparator {
            let trailingW: CGFloat = item.hasSubmenu
                ? 14 // chevron image view width
                : shortcutWidth(for: item.keyEquivalent ?? "")
            // +16: empirical slack so titles never truncate below the cap
            let total = titleX + titleWidth(for: item.title)
                + titleTrailingGap + trailingW + trailingMargin + 16
            maxWidth = max(maxWidth, total)
        }
        return min(maxWindowWidth, max(minWindowWidth, ceil(maxWidth)))
    }

    // Resize the window so it exactly fits the current table content.
    private func resizeWindowToFitContent() {
        let contentH = tableContentHeight()
        let height = contentH + titleBarHeight + Self.bottomMargin
        var frame = submenuWindow.frame
        frame.origin.y += frame.size.height - height  // keep the top edge fixed
        frame.size.height = height
        frame.size.width = windowWidth
        submenuWindow.setFrame(frame, display: true)
        // Pin the table to its content height. As a scroll-view documentView
        // it doesn't auto-shrink when the clip does, so a stale taller frame
        // would let the scroll view scroll past the rows.
        tableView.frame.size.height = contentH
    }

    // Reuse this window for a different menu item's submenu instead of
    // destroying and recreating the window (which is slow). The window stays
    // on screen; only its contents and size change. showWindow() repositions.
    func reconfigure(title: String, menuItems: [MenuItem], parentMenuItem: MenuItem?) {
        // Collapse any grandchild submenu before swapping contents
        closeSubmenu()

        self.title = title
        self.menuItems = menuItems
        self.parentMenuItem = parentMenuItem
        self.hoveredRow = nil
        self.isDragging = false
        self.windowWidth = Self.computeContentWidth(for: menuItems)

        submenuWindow.title = title
        tableView.tableColumns.first?.width = windowWidth

        tableView.reloadData()
        resizeWindowToFitContent()
    }

    // Opens menuItem's submenu at the given row, reusing the existing child
    // window when one is already on screen so switching is instant.
    private func presentSubmenu(for menuItem: MenuItem, at row: Int) {
        let submenuItems = MenuExtractor.submenuItems(for: menuItem)
        guard !submenuItems.isEmpty else { return }

        if let child = childSubmenuController {
            child.reconfigure(title: menuItem.title, menuItems: submenuItems, parentMenuItem: menuItem)
            child.showWindow(rightOf: submenuWindow, alignedToRow: row)
        } else {
            let child = makeChildController(title: menuItem.title,
                                            menuItems: submenuItems,
                                            parentMenuItem: menuItem)
            childSubmenuController = child
            child.showWindow(rightOf: submenuWindow, alignedToRow: row)
        }
        childSubmenuRow = row
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
        child.dismissChain = { [weak self] in
            guard let self = self else { return }
            if self.isTornOff {
                // Torn-off ancestor: close everything below it, but stay open
                self.closeSubmenu()
                self.updateAllRowHighlights()
            } else {
                self.dismissChain?()
            }
        }
        child.onPointerEntered = { [weak self] in
            guard let self = self else { return }
            if !self.childHasMouse {
                self.childHasMouse = true
                self.updateAllRowHighlights()
            }
            self.onPointerEntered?()  // propagate up the chain
        }
        return child
    }

    // Briefly blink a row's highlight (like a native menu) then run completion.
    // The blink drives the same updateRowHighlight() path as hover, so it uses
    // the identical highlight color.
    private func flashRow(_ row: Int, completion: @escaping () -> Void) {
        var step = 0
        let totalSteps = 4 // off, on, off, on
        flashState = (row, false)
        updateRowHighlight(forRow: row)
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            step += 1
            self.flashState = (row, step % 2 == 0)
            self.updateRowHighlight(forRow: row)
            if step >= totalSteps {
                timer.invalidate()
                self.flashState = nil
                self.updateRowHighlight(forRow: row)
                completion()
            }
        }
    }

    // Flash the clicked row, perform its action, then collapse the menu chain
    // up to the main menu or the first torn-off window.
    private func performAction(_ element: AXUIElement, at row: Int) {
        flashRow(row) { [weak self] in
            guard let self = self else { return }
            self.targetApp?.activate(options: [])
            usleep(50000)
            AXUIElementPerformAction(element, kAXPressAction as CFString)

            if self.isTornOff {
                self.closeSubmenu()
                self.updateAllRowHighlights()
            } else {
                self.dismissChain?()
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

        // orderFront only (no makeKey) - matches the main menu, avoids a
        // focus-window flicker when the submenu appears.
        submenuWindow.orderFrontRegardless()
    }

    // animated: fade the window out when genuinely closing the menu. Pass
    // false when switching between sibling submenus so the swap is instant.
    func hideWindow(animated: Bool = true) {
        // Only hide if not torn off
        guard !isTornOff else { return }

        // Notify parent before hiding
        onWillHide?()

        // Hide child submenu first (unless they're torn off)
        childSubmenuController?.hideWindow(animated: animated)
        childSubmenuController = nil
        childSubmenuRow = nil
        hoveredRow = nil

        if animated {
            // Fade out, then order out. The strong self capture keeps the
            // controller (and its window) alive for the animation's duration.
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                submenuWindow.animator().alphaValue = 0
            }, completionHandler: {
                self.submenuWindow.orderOut(nil)
                self.submenuWindow.alphaValue = 1
            })
        } else {
            submenuWindow.orderOut(nil)
        }
    }

    func clearHighlightAndHide() {
        // Clear child references without hiding (for when parent needs to update)
        childSubmenuController?.hideWindow()
        childSubmenuController = nil
        childSubmenuRow = nil

        // Update highlights
        for i in 0..<tableView.numberOfRows {
            updateRowHighlight(forRow: i)
        }

        hideWindow()
    }
}

// MARK: - NSTableViewDataSource
extension SubmenuWindowController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return visibleMenuItems.count
    }
}

// MARK: - NSTableViewDelegate
extension SubmenuWindowController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if row >= 0 && row < visibleMenuItems.count && visibleMenuItems[row].isSeparator {
            return separatorRowHeight
        }
        return rowHeight
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellIdentifier = NSUserInterfaceItemIdentifier("MenuItemCell")

        var cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView

        if cell == nil {
            // Create with the correct frame up front: subviews use autoresizing
            // masks, and a zero-size initial frame would distort their margins
            // when the table resizes the cell to the column width.
            cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: rowHeight))
            cell?.identifier = cellIdentifier
            cell?.wantsLayer = true

            // Rounded selection highlight - a material fill, shown/hidden by
            // updateRowHighlight(). Full row height (no gap between items).
            let backgroundView = NSVisualEffectView(frame: CGRect(x: 6, y: 0, width: windowWidth - 12, height: rowHeight))
            backgroundView.material = .selection
            backgroundView.blendingMode = .withinWindow
            backgroundView.state = .active
            backgroundView.isEmphasized = true
            backgroundView.wantsLayer = true
            backgroundView.layer?.cornerRadius = 8
            backgroundView.layer?.cornerCurve = .continuous
            backgroundView.layer?.masksToBounds = true
            backgroundView.identifier = NSUserInterfaceItemIdentifier("BackgroundView")
            backgroundView.isHidden = true
            cell?.addSubview(backgroundView)

            // All fields span the full row height; single-line labels center
            // their text vertically, so leading/label/trailing stay aligned.

            // Mark character (e.g. checkmark) on the left - wide frame so the
            // glyph isn't cramped, with slight leading padding
            let markField = CenteredLabel(frame: NSRect(x: 8, y: 0, width: 22, height: rowHeight))
            markField.isBordered = false
            markField.backgroundColor = .clear
            markField.isEditable = false
            markField.isSelectable = false
            markField.drawsBackground = false
            markField.alignment = .center
            markField.font = NSFont.systemFont(ofSize: 12, weight: .bold)
            markField.identifier = NSUserInterfaceItemIdentifier("MarkField")
            cell?.addSubview(markField)

            // Keyboard shortcut / chevron on the right
            let shortcutWidth: CGFloat = 56
            let shortcutField = CenteredLabel(frame: NSRect(x: windowWidth - 16 - shortcutWidth, y: 0, width: shortcutWidth, height: rowHeight))
            shortcutField.isBordered = false
            shortcutField.backgroundColor = .clear
            shortcutField.isEditable = false
            shortcutField.isSelectable = false
            shortcutField.drawsBackground = false
            shortcutField.alignment = .right
            shortcutField.font = NSFont.systemFont(ofSize: 13)
            shortcutField.usesSingleLineMode = true
            shortcutField.identifier = NSUserInterfaceItemIdentifier("ShortcutField")
            cell?.addSubview(shortcutField)

            // Disclosure chevron (SF Symbol) for submenu items, sized to match
            // the leading mark glyph
            let chevronView = NSImageView(frame: NSRect(x: windowWidth - Self.trailingMargin - 14, y: 0, width: 14, height: rowHeight))
            chevronView.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .bold))
            chevronView.imageScaling = .scaleNone
            chevronView.imageAlignment = .alignCenter
            chevronView.identifier = NSUserInterfaceItemIdentifier("ChevronView")
            cell?.addSubview(chevronView)

            // Item title in the middle
            let textField = CenteredLabel(frame: NSRect(x: Self.titleX, y: 0, width: windowWidth - 80, height: rowHeight))
            textField.isBordered = false
            textField.backgroundColor = .clear
            textField.isEditable = false
            textField.isSelectable = false
            textField.drawsBackground = false
            textField.alignment = .left
            textField.usesSingleLineMode = true
            textField.lineBreakMode = .byTruncatingTail

            cell?.addSubview(textField)
            cell?.textField = textField
        }

        let menuItem = visibleMenuItems[row]

        let markField = cell?.subviews.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("MarkField") }) as? NSTextField
        let shortcutField = cell?.subviews.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("ShortcutField") }) as? NSTextField
        let chevronView = cell?.subviews.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("ChevronView") }) as? NSImageView

        // Frame the fixed-position subviews explicitly each time: cells are
        // reused across reconfigure() where windowWidth changes, and there are
        // no autoresizing masks (which would skew widths after a cell resize).
        cell?.subviews.first { $0.identifier == NSUserInterfaceItemIdentifier("BackgroundView") }?
            .frame = NSRect(x: 6, y: 0, width: windowWidth - 12, height: rowHeight)
        markField?.frame = NSRect(x: 8, y: 0, width: 22, height: rowHeight)

        // Handle separators
        if menuItem.isSeparator {
            cell?.textField?.isHidden = true
            markField?.isHidden = true
            shortcutField?.isHidden = true
            chevronView?.isHidden = true

            // Add the separator line if not already present, then position
            // and colour it (centered in the shorter separator row)
            let separatorId = NSUserInterfaceItemIdentifier("Separator")
            let line: NSView
            if let existing = cell?.subviews.first(where: { $0.identifier == separatorId }) {
                line = existing
            } else {
                let v = NSView()
                v.wantsLayer = true
                v.identifier = separatorId
                cell?.addSubview(v)
                line = v
            }
            line.frame = NSRect(x: 8, y: separatorRowHeight / 2 - 0.5, width: windowWidth - 16, height: 1)
            line.layer?.backgroundColor = Self.separatorLineColor.cgColor
        } else {
            let titleX = Self.titleX
            let trailingX = windowWidth - Self.trailingMargin

            cell?.textField?.isHidden = false
            cell?.textField?.stringValue = menuItem.title
            cell?.textField?.font = NSFont.systemFont(ofSize: 13)
            cell?.textField?.textColor = menuItem.isEnabled ? .labelColor : .quaternaryLabelColor

            // Leading mark (checkmark / diamond), shown in outline style
            markField?.isHidden = false
            markField?.stringValue = Self.outlineMark(menuItem.markChar ?? "")
            markField?.textColor = menuItem.isEnabled ? .labelColor : .quaternaryLabelColor

            // Trailing: an SF Symbol chevron for submenu items, otherwise the
            // keyboard shortcut. titleRight marks where the title must stop.
            var titleRight = trailingX
            if menuItem.hasSubmenu {
                chevronView?.isHidden = false
                chevronView?.contentTintColor = menuItem.isEnabled ? .labelColor : .quaternaryLabelColor
                shortcutField?.isHidden = true
                // Trailing chevron sits inside the selection bounds
                let chevronW = chevronView?.frame.width ?? 14
                chevronView?.frame = NSRect(x: trailingX - chevronW, y: 0, width: chevronW, height: rowHeight)
                titleRight = trailingX - chevronW
            } else {
                chevronView?.isHidden = true
                shortcutField?.isHidden = false
                let key = menuItem.keyEquivalent ?? ""
                shortcutField?.font = NSFont.systemFont(ofSize: 13)
                shortcutField?.attributedStringValue = NSAttributedString(
                    string: key,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 13),
                        .foregroundColor: NSColor.quaternaryLabelColor,
                        .kern: 2.0
                    ]
                )
                // Use the shared width measurement so the title's budgeted
                // space (in computeContentWidth) matches its actual space.
                let w = Self.shortcutWidth(for: key)
                shortcutField?.frame = NSRect(x: trailingX - w, y: 0, width: w, height: rowHeight)
                titleRight = trailingX - w
            }
            cell?.textField?.frame = NSRect(
                x: titleX, y: 0, width: max(0, titleRight - titleX - Self.titleTrailingGap), height: rowHeight)

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
        let menuItem = visibleMenuItems[row]
        return menuItem.isEnabled && !menuItem.isSeparator
    }

    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        // Update row background based on whether it has an open submenu
        updateRowHighlight(forRow: row)
    }

    private func updateRowHighlight(forRow row: Int) {
        guard let cellView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView else { return }

        // A flashing row's blink state takes precedence over everything else
        let isHighlighted: Bool
        if let flashState = flashState, flashState.row == row {
            isHighlighted = flashState.on
        } else {
            // Only enabled, non-separator rows can be highlighted
            let hoverable = tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false
            if isTornOff {
                // A torn-off menu is standalone: hover highlights only while
                // click-dragging, or - once a submenu is open - other submenu
                // items (leaf rows aren't highlighted on hover).
                isHighlighted = hoverable
                    && (childSubmenuRow == row
                        || (hoveredRow == row && isDragging)
                        || (hoveredRow == row && childSubmenuRow != nil && isSubmenuRow(row)))
            } else {
                isHighlighted = hoverable && (childSubmenuRow == row || hoveredRow == row)
            }
        }

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

    private func handleMouseClickedRow(_ row: Int) {
        // Check if row is selectable (not disabled or separator)
        guard tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false else {
            return
        }

        let menuItem = visibleMenuItems[row]

        // Clicking the item whose submenu is already open: a torn-off menu
        // toggles it closed; an attached submenu leaves it open.
        if childSubmenuRow == row {
            if isTornOff {
                closeSubmenu()
                updateAllRowHighlights()
            }
            return
        }

        let submenuItems = menuItem.hasSubmenu ? MenuExtractor.submenuItems(for: menuItem) : []
        if !submenuItems.isEmpty {
            presentSubmenu(for: menuItem, at: row)
        } else if let element = menuItem.element {
            // Leaf item - flash, perform the action, collapse the chain
            performAction(element, at: row)
        }
    }

    // Handle mouse up - execute leaf actions; submenus open on mouse down
    private func handleMouseUp(_ row: Int, wasDragged: Bool) {
        isDragging = false
        // A click can also raise this window on mouse-up; keep the chain on top
        defer {
            DispatchQueue.main.async { [weak self] in self?.raiseSubmenuChain() }
        }
        guard row >= 0 && row < visibleMenuItems.count else { return }
        guard tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false else { return }

        let menuItem = visibleMenuItems[row]
        guard let element = menuItem.element else { return }

        // A click-drag released on a submenu item closes that submenu
        if menuItem.hasSubmenu {
            if wasDragged, childSubmenuRow == row {
                closeSubmenu()
                updateAllRowHighlights()
            }
            return
        }

        // Leaf item - flash, perform the action, collapse the chain
        performAction(element, at: row)
    }

    // Handle long press release - close menus
    private func handleMouseLongPressReleased(_ row: Int) {
        closeSubmenu()
        hoveredRow = nil
        isDragging = false
        updateAllRowHighlights()
    }

    // Execute action at row (called from parent window)
    func executeActionAtRow(_ row: Int) {
        guard row >= 0 && row < visibleMenuItems.count else { return }
        guard tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false else { return }

        let menuItem = visibleMenuItems[row]
        guard let element = menuItem.element else { return }

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

        // Use the pre-extracted submenu tree (falls back to on-demand)
        if menuItem.hasSubmenu, let element = menuItem.element {
            let submenuItems = MenuExtractor.submenuItems(for: menuItem)

            if !submenuItems.isEmpty {
                // Close any existing child submenu
                childSubmenuController?.hideWindow()

                // Create and show new child submenu
                childSubmenuController = SubmenuWindowController(
                    title: menuItem.title,
                    menuItems: submenuItems,
                    targetApp: targetApp,
                    parentMenuItem: menuItem
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
