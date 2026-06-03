import Cocoa

/// A custom NSPanel that doesn't steal focus from other applications
/// when clicked or dragged. This allows the window to remain interactive
/// (draggable) while keeping the original application as the frontmost app.
class NonActivatingWindow: NSPanel {
    var onRightMouseDown: ((NSEvent) -> Void)?

    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return false
    }

    // Don't let AppKit push the window out of the menu-bar area, so it can
    // sit flush with the top of the screen (e.g. when the menu bar is hidden).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }


    override func rightMouseDown(with event: NSEvent) {
        onRightMouseDown?(event)
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)

        // Panel-specific settings
        // self.isFloatingPanel = true TODO
        self.becomesKeyOnlyIfNeeded = true  // Allow becoming key when clicked
        self.hidesOnDeactivate = false
        self.worksWhenModal = true

        // Disable the system fade-in/out animation when the window is shown
        self.animationBehavior = .none

        setupBackground()
    }

    private func setupBackground() {
        if NeXTMenusRendering.useGlassEffects {
            let visualEffectView = NSVisualEffectView(frame: contentView?.bounds ?? .zero)
            visualEffectView.autoresizingMask = [.width, .height]
            visualEffectView.material = .menu
            visualEffectView.blendingMode = .behindWindow
            visualEffectView.state = .active
            visualEffectView.alphaValue = 1
            visualEffectView.wantsLayer = true
            visualEffectView.layer?.cornerRadius = 10
            visualEffectView.layer?.cornerCurve = .continuous
            visualEffectView.layer?.masksToBounds = true
            self.contentView = visualEffectView
            self.isOpaque = false
            self.backgroundColor = .clear
            return
        }

        let backgroundView = NSView(frame: contentView?.bounds ?? .zero)
        backgroundView.autoresizingMask = [.width, .height]
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = NeXTMenusRendering.windowBackgroundColor.cgColor
        backgroundView.layer?.cornerRadius = 10
        backgroundView.layer?.cornerCurve = .continuous
        backgroundView.layer?.masksToBounds = true
        self.contentView = backgroundView

        self.isOpaque = true
        self.backgroundColor = NeXTMenusRendering.windowBackgroundColor
    }
}
