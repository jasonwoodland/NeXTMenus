import Cocoa

class HoverTableView: NSTableView {
    var onMouseMoved: ((Int) -> Void)?  // Hover with no button pressed
    var onMouseDraggedOverRow: ((Int) -> Void)?  // Drag with button pressed
    var onMouseDown: ((Int) -> Void)?
    var onMouseUp: ((Int, Bool) -> Void)?  // (row, wasDragged)
    var onMouseLongPressReleased: ((Int) -> Void)?
    var onMouseExited: (() -> Void)?  // Mouse left the table entirely
    var onRightMouseDown: ((NSEvent) -> Void)?

    private var mouseDownRow: Int = -1
    private var mouseDownTimestamp: Date?
    private var hasDraggedToNewRow = false
    private var trackingArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        // .activeAlways so hover events still fire when this window is not key
        // (e.g. after a child submenu window has taken key status)
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseMoved(with event: NSEvent) {
        let locationInView = self.convert(event.locationInWindow, from: nil)
        let row = self.row(at: locationInView)
        onMouseMoved?(row)
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }

    override func mouseDown(with event: NSEvent) {
        // Note: deliberately not making the window key/front on click, so a
        // click in a menu doesn't focus or raise it.

        let locationInView = self.convert(event.locationInWindow, from: nil)
        let row = self.row(at: locationInView)

        mouseDownRow = row
        mouseDownTimestamp = Date()
        hasDraggedToNewRow = false

        // Notify parent of mouse down
        if row >= 0 {
            onMouseDown?(row)
        }

        // Don't call super - we'll handle everything ourselves
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownRow >= 0 else {
            mouseDownRow = -1
            mouseDownTimestamp = nil
            hasDraggedToNewRow = false
            return
        }

        // Check if this was a long press (>500ms) - but only if the mouse
        // never moved to a different row. A slow click-drag also exceeds
        // 500ms and must not be treated as a long press.
        if let timestamp = mouseDownTimestamp {
            let duration = Date().timeIntervalSince(timestamp)
            if duration > 0.5 && mouseDownRow >= 0 && !hasDraggedToNewRow {
                onMouseLongPressReleased?(mouseDownRow)
                mouseDownRow = -1
                mouseDownTimestamp = nil
                hasDraggedToNewRow = false
                return
            }
        }

        // Not a long press - notify parent at current mouse location
        let locationInView = self.convert(event.locationInWindow, from: nil)
        let row = self.row(at: locationInView)
        onMouseUp?(row, hasDraggedToNewRow)

        mouseDownRow = -1
        mouseDownTimestamp = nil
        hasDraggedToNewRow = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard mouseDownRow >= 0 else { return }

        let locationInView = self.convert(event.locationInWindow, from: nil)
        let row = self.row(at: locationInView)

        // Track if we've moved to a different row than where we pressed down
        if row != mouseDownRow {
            hasDraggedToNewRow = true
        }

        // Notify parent of drag
        onMouseDraggedOverRow?(row)
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightMouseDown?(event)
    }

    // Get row at a global screen point (for cross-window hover detection)
    func rowAtScreenPoint(_ screenPoint: NSPoint) -> Int {
        guard let window = self.window else { return -1 }

        // Convert screen point to window coordinates
        let screenRect = NSRect(origin: screenPoint, size: .zero)
        let windowRect = window.convertFromScreen(screenRect)
        let windowPoint = windowRect.origin

        // Convert window point to view coordinates
        let viewPoint = self.convert(windowPoint, from: nil)

        return self.row(at: viewPoint)
    }
}
