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


    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)

        // Panel-specific settings to prevent activation
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = false
        self.hidesOnDeactivate = false
        self.worksWhenModal = true

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

        // Set the visual effect view as the content view
        self.contentView = visualEffectView

        // Make window background transparent
        self.isOpaque = false
        self.backgroundColor = .clear
    }
}
