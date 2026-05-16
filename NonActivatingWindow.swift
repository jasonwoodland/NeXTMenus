import Cocoa

/// A custom NSPanel that doesn't steal focus from other applications
/// when clicked or dragged. This allows the window to remain interactive
/// (draggable) while keeping the original application as the frontmost app.
class NonActivatingWindow: NSPanel {

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


    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)

        // Panel-specific settings
        // self.isFloatingPanel = true TODO
        self.becomesKeyOnlyIfNeeded = true  // Allow becoming key when clicked
        self.hidesOnDeactivate = false
        self.worksWhenModal = true

        // Disable the system fade-in/out animation when the window is shown
        self.animationBehavior = .none

        // Setup translucent glass appearance
        setupGlassEffect()
    }

    private func setupGlassEffect() {
        // Create visual effect view for liquid glass appearance
        let visualEffectView = NSVisualEffectView(frame: contentView?.bounds ?? .zero)
        visualEffectView.autoresizingMask = [.width, .height]

        // Use hudWindow for modern liquid glass translucent effect
        visualEffectView.material = .menu
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active

        // Make the visual effect view transparent
        visualEffectView.alphaValue = 1

        // Round the glass slightly tighter than the system window corner.
        // Tune `cornerRadius` to taste.
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 10
        visualEffectView.layer?.cornerCurve = .continuous
        visualEffectView.layer?.masksToBounds = true

        // Set the visual effect view as the content view
        self.contentView = visualEffectView

        // Make window background transparent
        self.isOpaque = false
        self.backgroundColor = .clear
    }
}
