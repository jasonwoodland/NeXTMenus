import Cocoa
#if SWIFT_PACKAGE
import NeXTMenusKit
#endif

private final class SubmenuScrollCaretView: NSView {
    private let onHoverChanged: (Bool) -> Void
    private var trackingArea: NSTrackingArea?
    private(set) var isHovered = false

    init(symbolName: String, onHoverChanged: @escaping (Bool) -> Void) {
        self.onHoverChanged = onHoverChanged
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NeXTMenusRendering.useGlassEffects
            ? NSColor.clear.cgColor
            : NeXTMenusRendering.windowBackgroundColor.cgColor

        if NeXTMenusRendering.useGlassEffects {
            let backgroundView = NSVisualEffectView(frame: .zero)
            backgroundView.material = .menu
            backgroundView.blendingMode = .behindWindow
            backgroundView.state = .active
            backgroundView.autoresizingMask = [.width, .height]
            addSubview(backgroundView)
        }

        let imageView = NSImageView(frame: .zero)
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        imageView.imageScaling = .scaleNone
        imageView.imageAlignment = .alignCenter
        imageView.contentTintColor = .tertiaryLabelColor
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        for subview in subviews {
            subview.frame = bounds
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden || !bounds.contains(point) ? nil : self
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isHovered else { return }
        isHovered = true
        onHoverChanged(true)
    }

    override func mouseExited(with event: NSEvent) {
        cancelHover()
    }

    func cancelHover() {
        guard isHovered else { return }
        isHovered = false
        onHoverChanged(false)
    }
}

class SubmenuWindowController: NSWindowController {
    private var submenuWindow: NSWindow!
    private var tableView: HoverTableView!
    private var scrollView: NSScrollView!
    private var scrollClipBoundsObserver: NSObjectProtocol?
    private var scrollUpCaretView: SubmenuScrollCaretView!
    private var scrollDownCaretView: SubmenuScrollCaretView!
    private var scrollTimer: Timer?
    private var scrollWheelRemainder: CGFloat = 0
    private var menuItems: [MenuItem] = []
    private var title: String = ""
    private var targetApp: NSRunningApplication?
    private var parentMenuItem: MenuItem? // Track the parent menu item
    private let rowHeight: CGFloat = 24
    private let separatorRowHeight: CGFloat = 12
    private let titleBarHeight: CGFloat = 28
    private let caretRowHeight: CGFloat = 24
    private let scrollRepeatInterval: TimeInterval = 0.05
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
    private var menuItemsVersion = 0
    private var visibleMenuItemsCache: (state: MenuModifierState, version: Int, items: [MenuItem])?
    private var checkableItemKeys = Set<String>()

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
                                                    trimSeparators: true)
        visibleMenuItemsCache = (state, menuItemsVersion, items)
        return items
    }

    private func invalidateVisibleMenuItemsCache() {
        visibleMenuItemsCache = nil
    }

    private func resetInteractionStateForVisibleItemsChange() {
        closeSubmenu()
        hoveredRow = nil
        isDragging = false
        childHasMouse = false
        flashState = nil
        pressedOpenSubmenuRow = nil
    }

    // State management for menu interactions
    private var hoveredRow: Int? // Currently highlighted row (visual only)
    private var isDragging: Bool = false // True while a click-drag is in progress
    private var suppressRowTrackingUntilMouseUp = false
    private var pressedOpenSubmenuRow: Int?

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
        let windowHeight = contentHeight + titleBarHeight + Self.bottomMargin - 1

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

        // Keep the title visible while using glass rendering by default.
        // Low-power opaque drawing can be enabled with NEXTMENUS_LOW_POWER=1.
        submenuWindow.titlebarAppearsTransparent = true
        submenuWindow.titleVisibility = .visible
        submenuWindow.isOpaque = !NeXTMenusRendering.useGlassEffects
        submenuWindow.backgroundColor = NeXTMenusRendering.useGlassEffects ? .clear : NeXTMenusRendering.windowBackgroundColor

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
        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self = self else { return event }

            if event.type == .leftMouseDown,
               self.shouldSuppressRowTrackingForWindowDragStart(event) {
                self.suppressRowTrackingUntilMouseUp = true
                self.hoveredRow = nil
                self.isDragging = false
                self.updateAllRowHighlights()
            } else if event.type == .leftMouseUp {
                self.suppressRowTrackingUntilMouseUp = false
            }

            let mouseLocation = NSEvent.mouseLocation

            if event.type == .leftMouseDragged,
               self.isDragging,
               let ownWindow = self.window,
               !ownWindow.frame.contains(mouseLocation),
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
                self.pressedOpenSubmenuRow = nil
                self.isDragging = false
                self.hoveredRow = nil
                self.updateAllRowHighlights()
                return nil
            }

            return event
        }
    }

    private func shouldSuppressRowTrackingForWindowDragStart(_ event: NSEvent) -> Bool {
        guard event.window === submenuWindow else { return false }

        // If the press starts outside an actual table row (titlebar, bottom
        // padding, or other draggable background), any later row under the
        // pointer is caused by the window moving with the mouse, not by a
        // deliberate menu click-drag.
        let tablePoint = tableView.convert(event.locationInWindow, from: nil)
        let row = tableView.row(at: tablePoint)
        return row < 0
    }

    private func setupGlobalClickMonitor() {
        // Monitor global mouse clicks
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, !self.isTornOff else { return }

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
                self.invalidateVisibleMenuItemsCache()

                // Reload the table to show/hide alternate menu items. Since
                // filtering can change row indexes, close any open child
                // submenu and clear row-index state before trusting rows again.
                DispatchQueue.main.async {
                    self.resetInteractionStateForVisibleItemsChange()
                    self.tableView.reloadData()
                    self.resizeWindowToFitContent()
                    self.updateAllRowHighlights()
                }
            }
        }
    }

    // Called by parent window when modifiers change
    func updateModifierFlags(_ flags: NSEvent.ModifierFlags) {
        currentModifierFlags = flags
        invalidateVisibleMenuItemsCache()

        // Re-extract submenu items when modifiers change
        // This is necessary because macOS provides different items based on modifiers
        if let parentMenuItem = getParentMenuItem(), let element = parentMenuItem.element {
            let newSubmenuItems = MenuExtractor.extractSubmenuItemsOnDemand(from: element)
            if !newSubmenuItems.isEmpty {
                self.menuItems = newSubmenuItems
                menuItemsVersion += 1
                invalidateVisibleMenuItemsCache()
            }
        }

        resetInteractionStateForVisibleItemsChange()
        tableView.reloadData()
        resizeWindowToFitContent()
        updateAllRowHighlights()
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
        scrollTimer?.invalidate()
        if let observer = scrollClipBoundsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func windowDidMove(_ notification: Notification) {
        // Ignore moves that are programmatic
        if isProgrammaticMove {
            return
        }

        // Any user-driven window movement is a window drag, not a menu
        // click-drag. Suppress row tracking immediately so rows under the
        // pointer don't briefly highlight before the tear-off threshold.
        suppressRowTrackingUntilMouseUp = true
        if hoveredRow != nil || isDragging {
            hoveredRow = nil
            isDragging = false
            updateAllRowHighlights()
        }

        // Only mark as torn off if the window has actually moved from its initial position
        if !isTornOff {
            let currentFrame = submenuWindow.frame
            let distanceMoved = sqrt(
                pow(currentFrame.origin.x - initialWindowFrame.origin.x, 2) +
                pow(currentFrame.origin.y - initialWindowFrame.origin.y, 2)
            )

            // Mark as torn off as soon as the drag crosses the threshold. If
            // we wait until movement stops, the mouse-up on the titlebar can
            // be handled as an off-row release and dismiss the attached chain
            // before the window becomes detached.
            if distanceMoved > 10 {
                moveDetectionTimer?.invalidate()
                moveDetectionTimer = nil
                isTornOff = true
                // Show close button for torn off windows
                submenuWindow.standardWindowButton(.closeButton)?.isHidden = false
                // Hover no longer selects once torn off - clear any stale
                // highlight immediately.
                hoveredRow = nil
                isDragging = false
                suppressRowTrackingUntilMouseUp = true
                updateAllRowHighlights()
                // Let the parent release this now-independent window.
                onTornOff?()
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

        resizeWindowToFitContent(relativeTo: parentWindow)

        let parentFrame = parentWindow.frame
        let xPos = parentFrame.maxX - 6  // shift 6pt left to overlap parent
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
        self.scrollView = scrollView
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

        tableView.onScrollWheel = { [weak self] event in
            self?.handleScrollWheel(event) ?? false
        }

        // Add table view to scroll view
        scrollView.documentView = tableView

        // Add scroll view to window
        contentView.addSubview(scrollView)

        scrollUpCaretView = SubmenuScrollCaretView(symbolName: "chevron.up") { [weak self] hovering in
            self?.setScrolling(.up, active: hovering)
        }
        scrollDownCaretView = SubmenuScrollCaretView(symbolName: "chevron.down") { [weak self] hovering in
            self?.setScrolling(.down, active: hovering)
        }
        scrollUpCaretView.isHidden = true
        scrollDownCaretView.isHidden = true
        contentView.addSubview(scrollUpCaretView)
        contentView.addSubview(scrollDownCaretView)

        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollClipBoundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.updateScrollCaretVisibility()
        }
    }

    private enum ScrollDirection {
        case up, down
    }

    private func setScrolling(_ direction: ScrollDirection, active: Bool) {
        scrollTimer?.invalidate()
        scrollTimer = nil
        guard active else { return }

        hoveredRow = nil
        isDragging = false
        updateAllRowHighlights()

        scrollTimer = Timer.scheduledTimer(withTimeInterval: scrollRepeatInterval, repeats: true) { [weak self] _ in
            self?.scrollByRows(direction)
        }
    }

    private func scrollByRows(_ direction: ScrollDirection) {
        guard scrollView != nil else { return }
        setScrollOffsetY(snappedScrollOffset(after: direction))
        updateHoverAfterScroll()
    }

    private func handleScrollWheel(_ event: NSEvent) -> Bool {
        guard scrollView != nil else { return false }
        let deltaY = event.scrollingDeltaY
        guard abs(deltaY) > 0.1 else { return true }

        scrollWheelRemainder += deltaY
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? rowHeight : 3
        guard abs(scrollWheelRemainder) >= threshold else { return true }

        scrollByRows(scrollWheelRemainder < 0 ? .down : .up)
        scrollWheelRemainder = 0
        return true
    }

    private func updateHoverAfterScroll() {
        guard !isPointerOverVisibleScrollCaret() else { return }
        guard submenuWindow.frame.contains(NSEvent.mouseLocation) else { return }
        let row = tableView.rowAtScreenPoint(NSEvent.mouseLocation)
        guard hoveredRow != row else { return }
        hoveredRow = row
        updateAllRowHighlights()
    }

    private func updateRowVisibilityForScrollCarets() {
        guard let contentView = submenuWindow.contentView else { return }

        var obscuredRects: [NSRect] = []
        if !scrollUpCaretView.isHidden {
            obscuredRects.append(contentView.convert(scrollUpCaretView.frame, to: tableView))
        }
        if !scrollDownCaretView.isHidden {
            obscuredRects.append(contentView.convert(scrollDownCaretView.frame, to: tableView))
        }

        for row in 0..<tableView.numberOfRows {
            guard let cellView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) else { continue }
            let rowRect = tableView.rect(ofRow: row)
            let isObscured = obscuredRects.contains { $0.intersects(rowRect) }
            cellView.alphaValue = isObscured ? 0 : 1
        }
    }

    private func clearHoverForScrollCaretIfNeeded() -> Bool {
        guard isPointerOverVisibleScrollCaret() else { return false }
        if hoveredRow != nil || isDragging {
            hoveredRow = nil
            isDragging = false
            updateAllRowHighlights()
        }
        return true
    }

    private func isPointerOverVisibleScrollCaret() -> Bool {
        guard let contentView = submenuWindow.contentView else { return false }
        let screenRect = NSRect(origin: NSEvent.mouseLocation, size: .zero)
        let windowPoint = submenuWindow.convertFromScreen(screenRect).origin
        let point = contentView.convert(windowPoint, from: nil)
        return (!scrollUpCaretView.isHidden && scrollUpCaretView.frame.contains(point))
            || (!scrollDownCaretView.isHidden && scrollDownCaretView.frame.contains(point))
    }

    private func maxScrollOffsetY() -> CGFloat {
        max(0, tableView.frame.height - scrollView.contentView.bounds.height)
    }

    private func snappedScrollOffset(after direction: ScrollDirection) -> CGFloat {
        let currentY = scrollView.contentView.bounds.origin.y
        let maxY = maxScrollOffsetY()
        let epsilon: CGFloat = 0.5
        guard tableView.numberOfRows > 0 else { return 0 }

        switch direction {
        case .down:
            for row in 0..<tableView.numberOfRows {
                let rowY = tableView.rect(ofRow: row).minY
                if rowY > currentY + epsilon {
                    return min(rowY, maxY)
                }
            }
            return maxY
        case .up:
            for row in stride(from: tableView.numberOfRows - 1, through: 0, by: -1) {
                let rowY = tableView.rect(ofRow: row).minY
                if rowY < currentY - epsilon {
                    return max(0, min(rowY, maxY))
                }
            }
            return 0
        }
    }

    private func setScrollOffsetY(_ y: CGFloat) {
        let clampedY = min(max(0, y), maxScrollOffsetY())
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateScrollCaretVisibility()
    }

    private func layoutScrollCaretViews(canScrollUp: Bool, canScrollDown: Bool) {
        guard let contentView = submenuWindow.contentView else { return }
        let bottomPadding = Self.bottomMargin - 1
        let scrollFrame = NSRect(
            x: 0,
            y: bottomPadding,
            width: contentView.bounds.width,
            height: max(rowHeight, contentView.bounds.height - titleBarHeight - bottomPadding)
        )
        scrollView.frame = scrollFrame

        scrollUpCaretView.frame = NSRect(
            x: scrollFrame.minX,
            y: scrollFrame.maxY - caretRowHeight,
            width: scrollFrame.width,
            height: caretRowHeight
        )
        scrollDownCaretView.frame = NSRect(
            x: scrollFrame.minX,
            y: scrollFrame.minY,
            width: scrollFrame.width,
            height: caretRowHeight
        )

        scrollView.layer?.mask = nil

        if scrollUpCaretView.superview == nil {
            contentView.addSubview(scrollUpCaretView, positioned: .above, relativeTo: scrollView)
        }
        if scrollDownCaretView.superview == nil {
            contentView.addSubview(scrollDownCaretView, positioned: .above, relativeTo: scrollUpCaretView)
        }
    }


    private func updateScrollCaretVisibility() {
        guard scrollView != nil else { return }
        let maxY = maxScrollOffsetY()
        let currentY = min(scrollView.contentView.bounds.origin.y, maxY)
        let canScrollUp = currentY > 0.5
        let canScrollDown = currentY < maxY - 0.5

        layoutScrollCaretViews(canScrollUp: canScrollUp, canScrollDown: canScrollDown)

        if !canScrollUp, scrollUpCaretView.isHovered {
            scrollUpCaretView.cancelHover()
        }
        if !canScrollDown, scrollDownCaretView.isHovered {
            scrollDownCaretView.cancelHover()
        }

        scrollUpCaretView.isHidden = !canScrollUp
        scrollDownCaretView.isHidden = !canScrollDown
        updateRowVisibilityForScrollCarets()

        if scrollView.contentView.bounds.origin.y > maxY {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func screenForSubmenu(relativeTo parentWindow: NSWindow? = nil) -> NSScreen? {
        if let screen = parentWindow?.screen ?? submenuWindow.screen {
            return screen
        }
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
    }

    private func availableWindowHeight(relativeTo parentWindow: NSWindow? = nil) -> CGFloat {
        guard let screen = screenForSubmenu(relativeTo: parentWindow) else { return .greatestFiniteMagnitude }
        let topY = parentWindow?.frame.maxY ?? submenuWindow.frame.maxY
        let bottomY = screen.frame.minY + NeXTMenusSettings.topLeftInset
        return max(titleBarHeight + rowHeight, topY - bottomY)
    }

    private func constrainedWindowHeight(forContentHeight contentH: CGFloat, relativeTo parentWindow: NSWindow? = nil) -> CGFloat {
        let desired = contentH + titleBarHeight + Self.bottomMargin - 1
        let available = availableWindowHeight(relativeTo: parentWindow)
        guard desired > available else { return desired }

        let availableListHeight = max(rowHeight, available - titleBarHeight - Self.bottomMargin + 1)
        let visibleRows = max(1, floor(availableListHeight / rowHeight))
        return visibleRows * rowHeight + titleBarHeight + Self.bottomMargin - 1
    }

    private func updateScrollLayout(resetToTop: Bool = false) {
        guard scrollView != nil else { return }
        let contentH = tableContentHeight()
        let documentH = contentH
        let maxY = max(0, documentH - scrollView.contentView.bounds.height)
        tableView.frame.size.height = documentH
        if resetToTop {
            setScrollOffsetY(0)
        } else if scrollView.contentView.bounds.origin.y > maxY {
            setScrollOffsetY(maxY)
        } else {
            updateScrollCaretVisibility()
        }
    }

    // MARK: - Mouse Event Handlers

    // Handle mouse hover (no button pressed) - visual highlight only
    private func handleMouseMoved(_ row: Int) {
        guard !suppressRowTrackingUntilMouseUp else { return }
        guard !clearHoverForScrollCaretIfNeeded() else { return }
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

    // Pointer left the table - clear the hover highlight (the open-submenu
    // row stays highlighted via childSubmenuRow).
    private func handleMouseExited() {
        if hoveredRow != nil {
            hoveredRow = nil
            updateAllRowHighlights()
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
        guard !suppressRowTrackingUntilMouseUp else { return }
        guard !clearHoverForScrollCaretIfNeeded() else { return }
        pressedOpenSubmenuRow = nil

        // A click raises this window above its open submenu; re-assert the
        // chain on top afterwards so the submenu stays focused/visible.
        defer {
            DispatchQueue.main.async { [weak self] in self?.raiseSubmenuChain() }
        }
        guard row >= 0 && row < visibleMenuItems.count else { return }
        guard tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false else { return }

        let menuItem = visibleMenuItems[row]
        if menuItem.hasSubmenu, childSubmenuRow == row {
            pressedOpenSubmenuRow = row
            if isTornOff {
                hoveredRow = row
                isDragging = true
                updateAllRowHighlights()
            }
            return
        }

        if isTornOff {
            hoveredRow = row
            isDragging = true
            updateAllRowHighlights()
        }

        // Open the submenu on press; leaf items act on mouse up
        if menuItem.hasSubmenu {
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
        guard !suppressRowTrackingUntilMouseUp else { return }
        guard !clearHoverForScrollCaretIfNeeded() else { return }

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
        let isInBounds = row >= 0 && row < visibleMenuItems.count
        let menuItem = isInBounds ? visibleMenuItems[row] : nil
        let intent = MenuInteractionPolicy.submenuOpenSubmenuIntent(
            hoveredRow: row,
            childSubmenuRow: childSubmenuRow,
            isDragging: isDragging,
            isInBounds: isInBounds,
            isSelectable: isInBounds && (tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false),
            isSeparator: menuItem?.isSeparator ?? false,
            hasSubmenu: menuItem?.hasSubmenu ?? false
        )

        switch intent {
        case .ignore:
            return
        case .close:
            closeSubmenu()
            updateAllRowHighlights()
        case .present(let row):
            guard row >= 0, row < visibleMenuItems.count else { return }
            presentSubmenu(for: visibleMenuItems[row], at: row)
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

    func containsScreenPointInChain(_ point: NSPoint) -> Bool {
        if submenuWindow.frame.contains(point) { return true }
        return childSubmenuController?.containsScreenPointInChain(point) ?? false
    }

    // Helper to update all row highlights
    private func updateAllRowHighlights() {
        for i in 0..<tableView.numberOfRows {
            updateRowHighlight(forRow: i)
        }
        updateRowVisibilityForScrollCarets()
    }

    private func closeSubmenu() {
        pressedOpenSubmenuRow = nil
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

    // Width occupied by the keyboard-shortcut text, computed from the same
    // fixed-cell layout ShortcutView uses, so window sizing and cell layout
    // can't diverge.
    private static func shortcutWidth(for key: String) -> CGFloat {
        return ShortcutView.intrinsicWidth(for: key)
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

    // Resize the window so it fits the table content without extending below
    // the screen edge (using the same top-left inset as the main menu).
    private func resizeWindowToFitContent(relativeTo parentWindow: NSWindow? = nil, resetScrollToTop: Bool = false) {
        let contentH = tableContentHeight()
        let height = constrainedWindowHeight(forContentHeight: contentH, relativeTo: parentWindow)
        var frame = submenuWindow.frame
        frame.origin.y += frame.size.height - height  // keep the top edge fixed
        frame.size.height = height
        frame.size.width = windowWidth
        submenuWindow.setFrame(frame, display: true)
        updateScrollLayout(resetToTop: resetScrollToTop)
    }

    // Reuse this window for a different menu item's submenu instead of
    // destroying and recreating the window (which is slow). The window stays
    // on screen; only its contents and size change. showWindow() repositions.
    func reconfigure(title: String, menuItems: [MenuItem], parentMenuItem: MenuItem?) {
        // Collapse any grandchild submenu before swapping contents
        closeSubmenu()

        self.title = title
        self.menuItems = menuItems
        checkableItemKeys.removeAll()
        rememberCheckableItems()
        menuItemsVersion += 1
        invalidateVisibleMenuItemsCache()
        self.parentMenuItem = parentMenuItem
        self.hoveredRow = nil
        self.isDragging = false
        self.pressedOpenSubmenuRow = nil
        self.windowWidth = Self.computeContentWidth(for: menuItems)

        submenuWindow.title = title
        tableView.tableColumns.first?.width = windowWidth

        tableView.reloadData()
        resizeWindowToFitContent(resetScrollToTop: true)
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
            self.hoveredRow = nil
            self.isDragging = false
            self.childHasMouse = false
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

    // Briefly flash a row's highlight off then on before running completion.
    // The flash drives the same updateRowHighlight() path as hover, so it uses
    // the identical highlight color.
    private func flashRow(_ row: Int, completion: @escaping () -> Void) {
        var step = 0
        let totalSteps = 2 // off, on
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

    // Perform the clicked row's action. Attached menus flash first and then
    // collapse; torn-off menus act immediately and stay open.
    private func performAction(_ element: AXUIElement, at row: Int) {
        if isTornOff {
            closeSubmenu()
            rememberCheckableItems()
            AXUIElementPerformAction(element, kAXPressAction as CFString)
            let didOptimisticallyToggle = optimisticallyToggleMarkIfNeeded(at: row)
            if !didOptimisticallyToggle {
                refreshTornOffMenuItemsAfterAction()
            }
            updateAllRowHighlights()
            return
        }

        flashRow(row) { [weak self] in
            guard let self = self else { return }
            self.targetApp?.activate(options: [])
            usleep(50000)
            AXUIElementPerformAction(element, kAXPressAction as CFString)
            self.dismissChain?()
        }
    }

    private func rememberCheckableItems() {
        for item in menuItems where item.markChar != nil {
            checkableItemKeys.insert(checkableKey(for: item))
        }
    }

    private func optimisticallyToggleMarkIfNeeded(at row: Int) -> Bool {
        guard isTornOff,
              row >= 0,
              row < visibleMenuItems.count,
              let sourceIndex = sourceMenuItemIndex(forVisibleRow: row) else { return false }

        let key = checkableKey(for: menuItems[sourceIndex])
        guard menuItems[sourceIndex].markChar != nil || checkableItemKeys.contains(key) else { return false }

        if menuItems[sourceIndex].markChar == nil {
            menuItems[sourceIndex].markChar = "✓"
            checkableItemKeys.insert(key)
        } else {
            menuItems[sourceIndex].markChar = nil
        }
        menuItemsVersion += 1
        invalidateVisibleMenuItemsCache()
        tableView.reloadData()
        updateAllRowHighlights()
        return true
    }

    private func sourceMenuItemIndex(forVisibleRow row: Int) -> Int? {
        guard row >= 0, row < visibleMenuItems.count else { return nil }
        let visibleItem = visibleMenuItems[row]
        let visibleKey = checkableKey(for: visibleItem)

        return menuItems.indices.first { index in
            let item = menuItems[index]
            if let visibleElement = visibleItem.element,
               let itemElement = item.element,
               CFEqual(itemElement, visibleElement) {
                return true
            }
            return checkableKey(for: item) == visibleKey
                && item.title == visibleItem.title
                && item.isSeparator == visibleItem.isSeparator
                && item.isAlternate == visibleItem.isAlternate
        }
    }

    private func checkableKey(for item: MenuItem) -> String {
        "\(item.title)|\(item.cmdChar ?? "")|\(item.cmdModifiers ?? -1)"
    }

    private func refreshTornOffMenuItemsAfterAction() {
        guard isTornOff else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self, self.isTornOff else { return }
            var didChange = false

            for index in self.menuItems.indices {
                guard let element = self.menuItems[index].element else { continue }
                let refreshedMark = self.markChar(for: element)
                if self.menuItems[index].markChar != refreshedMark {
                    self.menuItems[index].markChar = refreshedMark
                    didChange = true
                }
            }

            guard didChange else { return }
            self.menuItemsVersion += 1
            self.invalidateVisibleMenuItemsCache()
            self.tableView.reloadData()
            self.updateAllRowHighlights()
        }
    }

    private func markChar(for element: AXUIElement) -> String? {
        var markValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXMenuItemMarkCharAttribute as CFString, &markValue)
        return (markValue as? String).flatMap { str -> String? in
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    func showWindow(rightOf parentWindow: NSWindow, alignedToRow row: Int? = nil) {
        // Position to the right of the parent window with tops aligned
        resizeWindowToFitContent(relativeTo: parentWindow, resetScrollToTop: true)
        let parentFrame = parentWindow.frame
        let xPos = parentFrame.maxX - 6  // shift 6pt left to overlap parent
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
        pressedOpenSubmenuRow = nil

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

            // Rounded selection highlight, shown/hidden by
            // updateRowHighlight(). Full row height (no gap between items).
            let backgroundView = NeXTMenusRendering.makeSelectionBackground(
                frame: CGRect(x: 6, y: 0, width: windowWidth - 12, height: rowHeight)
            )
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

            // Keyboard shortcut on the right - rendered as fixed-width cells
            // (matching the native menu) by ShortcutView. Position is set per
            // configure() since the cell count varies.
            let shortcutView = ShortcutView(frame: NSRect(x: windowWidth - 16, y: 0, width: 0, height: rowHeight))
            shortcutView.identifier = NSUserInterfaceItemIdentifier("ShortcutField")
            cell?.addSubview(shortcutView)

            // Disclosure chevron (SF Symbol) for submenu items, sized to match
            // the leading mark glyph
            let chevronView = NSImageView(frame: NSRect(x: windowWidth - Self.trailingMargin - 14, y: 0, width: 14, height: rowHeight))
            chevronView.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .bold))
            chevronView.imageScaling = .scaleNone
            chevronView.imageAlignment = .alignRight
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
        let shortcutField = cell?.subviews.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("ShortcutField") }) as? ShortcutView
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
            line.frame = NSRect(x: 16, y: separatorRowHeight / 2 - 0.5, width: windowWidth - 32, height: 1)
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
                // Use the shared width measurement so the title's budgeted
                // space (in computeContentWidth) matches its actual space.
                let w = Self.shortcutWidth(for: key)
                shortcutField?.frame = NSRect(x: trailingX - w, y: 0, width: w, height: rowHeight)
                shortcutField?.configure(with: key)
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
        updateRowVisibilityForScrollCarets()
    }

    private func updateRowHighlight(forRow row: Int) {
        guard let cellView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView else { return }

        let flash = flashState.map { MenuRowFlash(row: $0.row, isOn: $0.on) }
        let appearance = MenuHighlightPolicy.submenuRowAppearance(
            row: row,
            isHoverable: tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false,
            isSubmenuRow: isSubmenuRow(row),
            hoveredRow: hoveredRow,
            childSubmenuRow: childSubmenuRow,
            childHasMouse: childHasMouse,
            isDragging: isDragging,
            isTornOff: isTornOff,
            flash: flash
        )

        let highlightView = cellView.subviews.first {
            $0.identifier == NSUserInterfaceItemIdentifier("BackgroundView")
        }
        highlightView?.isHidden = !appearance.isHighlighted
        // The open-submenu row de-emphasizes (different material, not the blue
        // selection) while the pointer is down in the child submenu.
        if let effect = highlightView as? NSVisualEffectView {
            effect.isEmphasized = appearance.isEmphasized
        }
        cellView.backgroundStyle = appearance.isHighlighted ? .emphasized : .normal
        // ShortcutView's text labels aren't covered by NSTableCellView's
        // textField propagation, so push the emphasis state to them too.
        let shortcutField = cellView.subviews.first {
            $0.identifier == NSUserInterfaceItemIdentifier("ShortcutField")
        } as? ShortcutView
        shortcutField?.setEmphasized(appearance.isHighlighted)
    }

    private func handleMouseClickedRow(_ row: Int) {
        // Check if row is selectable (not disabled or separator)
        guard tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false else {
            return
        }

        let menuItem = visibleMenuItems[row]

        // Clicking the item whose submenu is already open is handled by the
        // mouse-up path. Attached submenus no-op; torn-off submenus close on
        // release so the press itself does not flicker the child closed/open.
        if childSubmenuRow == row {
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
        let pressedOpenSubmenuRow = pressedOpenSubmenuRow
        self.pressedOpenSubmenuRow = nil
        if clearHoverForScrollCaretIfNeeded() { return }
        isDragging = false
        // A click can also raise this window on mouse-up; keep the chain on top
        defer {
            DispatchQueue.main.async { [weak self] in self?.raiseSubmenuChain() }
        }
        // Released off any menu item or outside the menu window - cancel the
        // whole attached tracking chain so later hover does not keep opening
        // submenus without a fresh mouse-down. Torn-off menus stay visible.
        if row < 0 {
            hoveredRow = nil
            closeSubmenu()
            updateAllRowHighlights()
            if isTornOff {
                isDragging = false
            } else {
                dismissChain?()
            }
            return
        }
        guard row < visibleMenuItems.count else { return }
        if !(tableView.delegate?.tableView?(tableView, shouldSelectRow: row) ?? false) {
            hoveredRow = nil
            closeSubmenu()
            updateAllRowHighlights()
            if !isTornOff {
                dismissChain?()
            }
            return
        }

        let menuItem = visibleMenuItems[row]

        if menuItem.hasSubmenu {
            if pressedOpenSubmenuRow == row, childSubmenuRow == row {
                if isTornOff {
                    closeSubmenu()
                    hoveredRow = nil
                    updateAllRowHighlights()
                }
                return
            }

            // A click-drag released on a submenu item closes that submenu
            if wasDragged, childSubmenuRow == row {
                closeSubmenu()
                updateAllRowHighlights()
            }
            return
        }

        guard let element = menuItem.element else { return }

        if isTornOff {
            hoveredRow = nil
            updateAllRowHighlights()
        }

        // Leaf item - flash, perform the action, collapse the chain
        performAction(element, at: row)
    }

    // Handle long press release - a slow click is still a click. Route
    // through the normal mouseup path so leaf actions fire and submenu
    // state stays correct.
    private func handleMouseLongPressReleased(_ row: Int) {
        handleMouseUp(row, wasDragged: false)
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

        // HoverTableView owns mouse-driven submenu/action behavior. Keep this
        // delegate path defensive only so an incidental selection cannot race
        // the mouse handlers and briefly close/reopen an already-open submenu.
        tableView.deselectRow(selectedRow)
    }
}
