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

/// Renders a keyboard-shortcut string as a series of fixed-width cells, like
/// the native macOS menu does. Modifier characters and SF Symbol substitutes
/// (globe, mic, etc.) are center-aligned in their cell; the final key
/// character is left-aligned. The trailing edge of the view sits at the
/// shortcut's last cell, so right-aligning the view across rows naturally
/// stacks each modifier column at the same x position.
class ShortcutView: NSView {
    /// Width of each modifier / SF-symbol cell.
    static let modifierCellWidth: CGFloat = 18
    /// Width of the trailing key cell.
    static let keyCellWidth: CGFloat = 18
    /// Negative spacing applied between cells - each cell overlaps the next
    /// by this many points so modifier symbols sit closer together.
    static let cellSpacing: CGFloat = -4
    /// Leading padding inside the key cell so the key letter doesn't butt up
    /// against the preceding modifier (compensating for cellSpacing).
    static let keyCellLeadingPadding: CGFloat = 2
    private static let font = NSFont.systemFont(ofSize: 13)
    private static let textColor = NSColor.quaternaryLabelColor

    /// Total width occupied by a shortcut, used for positioning.
    static func intrinsicWidth(for shortcut: String) -> CGFloat {
        let count = shortcut.unicodeScalars.count
        guard count > 0 else { return 0 }
        return (modifierCellWidth + cellSpacing) * CGFloat(count - 1) + keyCellWidth
    }

    /// Replace the cells in this view with one per character of `shortcut`.
    func configure(with shortcut: String) {
        subviews.forEach { $0.removeFromSuperview() }
        let scalars = Array(shortcut.unicodeScalars)
        var x: CGFloat = 0
        for (i, scalar) in scalars.enumerated() {
            let isLast = i == scalars.count - 1
            let cellWidth = isLast ? Self.keyCellWidth : Self.modifierCellWidth
            let cellFrame = NSRect(x: x, y: 0, width: cellWidth, height: bounds.height)
            addSubview(makeCell(for: scalar, frame: cellFrame, leftAlign: isLast))
            x += cellWidth + Self.cellSpacing
        }
    }

    /// Propagate the row's selection state to each text cell's NSTextFieldCell
    /// so the modifier/key characters switch to the emphasized (white) color
    /// when the row is highlighted. NSImageView's contentTintColor already
    /// auto-translates against the selection background, so symbol cells need
    /// no help here.
    func setEmphasized(_ emphasized: Bool) {
        let style: NSView.BackgroundStyle = emphasized ? .emphasized : .normal
        for cell in subviews {
            if let label = cell as? NSTextField {
                label.cell?.backgroundStyle = style
            }
        }
    }

    private func makeCell(for scalar: Unicode.Scalar, frame: NSRect, leftAlign: Bool) -> NSView {
        if let symbolName = Self.sfSymbolReplacement(for: scalar),
           let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)) {
            image.isTemplate = true

            // NSImageView centers the image's full bounds rather than the
            // visible glyph - SF Symbols carry padding around the symbol for
            // text-baseline alignment, so the visible content ends up
            // off-center. Frame an inner image view explicitly so the
            // symbol's alignment rect centers horizontally in the cell, and
            // its vertical center matches the surrounding text's cap-height
            // midline (so ⌘/⌃/⌥/⇧ glyphs and the symbol all line up).
            let container = NSView(frame: frame)
            let alignRect = image.alignmentRect
            let imgSize = image.size
            let font = Self.font
            let lineHeight = ceil(font.ascender - font.descender)
            let textBaselineY = (frame.height - lineHeight) / 2 + (-font.descender)
            let textCapMidY = textBaselineY + font.capHeight / 2

            let vx: CGFloat = leftAlign
                ? Self.keyCellLeadingPadding - alignRect.origin.x
                : (frame.width - alignRect.width) / 2 - alignRect.origin.x
            let vy: CGFloat = textCapMidY - (alignRect.origin.y + alignRect.height / 2)

            let imageView = NSImageView(frame: NSRect(x: vx, y: vy, width: imgSize.width, height: imgSize.height))
            imageView.image = image
            imageView.imageScaling = .scaleNone
            imageView.imageAlignment = .alignCenter
            imageView.contentTintColor = Self.textColor
            container.addSubview(imageView)
            return container
        }
        // For the key cell, inset the label by `keyCellLeadingPadding` so the
        // letter sits a touch right of the cell's left edge (compensating for
        // the negative inter-cell spacing).
        let labelFrame: NSRect = leftAlign
            ? NSRect(x: frame.origin.x + Self.keyCellLeadingPadding,
                     y: frame.origin.y,
                     width: frame.width - Self.keyCellLeadingPadding,
                     height: frame.height)
            : frame
        let label = CenteredLabel(frame: labelFrame)
        label.isBordered = false
        label.backgroundColor = .clear
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.alignment = leftAlign ? .left : .center
        label.font = Self.font
        label.textColor = Self.textColor
        label.stringValue = String(scalar)
        return label
    }

    /// Emoji-style keyboard glyphs that macOS reports in shortcut characters
    /// (Fn/Globe modifier, dictation mic, etc.) mapped to SF Symbol names.
    private static func sfSymbolReplacement(for scalar: Unicode.Scalar) -> String? {
        switch scalar.value {
        case 0x1F3A4, 0x1F399: return "mic"   // 🎤, 🎙
        case 0x1F310:          return "globe" // 🌐
        default:               return nil
        }
    }
}
