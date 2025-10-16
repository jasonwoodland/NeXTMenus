import Cocoa

class HoverTableView: NSTableView {
    var onMouseDraggedOverRow: ((Int) -> Void)?
    var onMouseClickedRow: ((Int) -> Void)?
    private var isMousePressed = false
    private var lastHoveredRow: Int = -1
    private var mouseDownRow: Int = -1

    override func mouseDown(with event: NSEvent) {
        print("HoverTableView mouseDown")

        // Make the window key to ensure it receives events
        self.window?.makeKey()

        let locationInView = self.convert(event.locationInWindow, from: nil)
        let row = self.row(at: locationInView)

        isMousePressed = true
        lastHoveredRow = row
        mouseDownRow = row

        // Don't call super - we'll handle everything ourselves
    }

    override func mouseUp(with event: NSEvent) {
        print("HoverTableView mouseUp")

        let locationInView = self.convert(event.locationInWindow, from: nil)
        let row = self.row(at: locationInView)

        // If mouse up on same row as mouse down, it's a click
        if row == mouseDownRow && row >= 0 {
            print("Clicked on row \(row)")
            onMouseClickedRow?(row)
        }

        isMousePressed = false
        lastHoveredRow = -1
        mouseDownRow = -1
    }

    override func mouseDragged(with event: NSEvent) {
        print("HoverTableView mouseDragged, isMousePressed: \(isMousePressed)")

        let locationInView = self.convert(event.locationInWindow, from: nil)
        let row = self.row(at: locationInView)

        print("HoverTableView handleMouseMove row: \(row), lastHoveredRow: \(lastHoveredRow)")

        if row >= 0 && row != lastHoveredRow {
            print("Calling onMouseDraggedOverRow callback for row \(row)")
            lastHoveredRow = row
            onMouseDraggedOverRow?(row)
        }
    }
}
