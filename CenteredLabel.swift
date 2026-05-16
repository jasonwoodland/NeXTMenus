import Cocoa

/// An `NSTextFieldCell` that vertically centers its single-line text within
/// the cell bounds. Plain `NSTextField` labels draw their text toward the top,
/// which leaves differently-sized labels visually unaligned.
class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        var titleRect = super.titleRect(forBounds: rect)
        // Center using the font's line metrics rather than the measured
        // content size. Content-based sizing shifts text with tall glyphs
        // (↩, ⌘, arrows), so shortcuts would sometimes look off-center.
        let lineHeight: CGFloat
        if let font = self.font {
            lineHeight = ceil(font.ascender - font.descender)
        } else {
            lineHeight = cellSize(forBounds: rect).height
        }
        titleRect.origin.y += (titleRect.height - lineHeight) / 2
        titleRect.size.height = lineHeight
        // Use the full width with no horizontal cell inset, so callers can
        // budget field widths exactly without text truncating.
        titleRect.origin.x = rect.origin.x
        titleRect.size.width = rect.width
        return titleRect
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: titleRect(forBounds: cellFrame), in: controlView)
    }
}

/// A label whose text stays vertically centered in its frame, so labels of
/// different font sizes line up on the same center line.
class CenteredLabel: NSTextField {
    override class var cellClass: AnyClass? {
        get { VerticallyCenteredTextFieldCell.self }
        set { }
    }
}
