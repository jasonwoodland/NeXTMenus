import Cocoa

enum NeXTMenusRendering {
    // Default to the original glass rendering. Set NEXTMENUS_LOW_POWER=1 to
    // use simple opaque drawing while profiling WindowServer CPU.
    static let useGlassEffects = ProcessInfo.processInfo.environment["NEXTMENUS_LOW_POWER"] != "1"

    static var windowBackgroundColor: NSColor {
        NSColor.windowBackgroundColor
    }

    static var selectionBackgroundColor: NSColor {
        NSColor.selectedContentBackgroundColor
    }

    static func makeSelectionBackground(frame: NSRect) -> NSView {
        if useGlassEffects {
            let backgroundView = NSVisualEffectView(frame: frame)
            backgroundView.material = .selection
            backgroundView.blendingMode = .withinWindow
            backgroundView.state = .active
            backgroundView.isEmphasized = true
            backgroundView.wantsLayer = true
            backgroundView.layer?.cornerRadius = 8
            backgroundView.layer?.cornerCurve = .continuous
            backgroundView.layer?.masksToBounds = true
            return backgroundView
        }

        let backgroundView = NSView(frame: frame)
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = selectionBackgroundColor.cgColor
        backgroundView.layer?.cornerRadius = 8
        backgroundView.layer?.cornerCurve = .continuous
        backgroundView.layer?.masksToBounds = true
        return backgroundView
    }
}
