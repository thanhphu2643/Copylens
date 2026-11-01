import AppKit

/// Dims every screen and lets the user drag out a region. Esc or right-click cancels.
final class SelectionOverlay {
    typealias Completion = (CGRect, NSScreen) -> Void

    private var panels: [NSPanel] = []
    private var completion: Completion?

    /// Called whenever the overlay goes away, whether a region was chosen or not.
    var onDismiss: (() -> Void)?

    var isActive: Bool { !panels.isEmpty }

    func begin(completion: @escaping Completion) {
        self.completion = completion
        panels = NSScreen.screens.map { screen in
            let panel = OverlayPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.setFrame(screen.frame, display: false)
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            panel.acceptsMouseMovedEvents = true
            panel.animationBehavior = .none
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.contentView = SelectionView(
                onSelect: { [weak self] rect in self?.finish(rect, screen) },
                onCancel: { [weak self] in self?.cancel() }
            )
            panel.orderFrontRegardless()
            return panel
        }
        let mouse = NSEvent.mouseLocation
        let active = panels.first { NSMouseInRect(mouse, $0.frame, false) } ?? panels.first
        active?.makeKey()
        NSCursor.crosshair.set()
    }

    func cancel() {
        panels.forEach { $0.orderOut(nil) }
        panels = []
        completion = nil
        NSCursor.arrow.set()
        onDismiss?()
    }

    private func finish(_ rect: CGRect, _ screen: NSScreen) {
        let completion = completion
        cancel()
        completion?(rect, screen)
    }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    private let onSelect: (CGRect) -> Void
    private let onCancel: () -> Void
    private var start: CGPoint?
    private var selection: CGRect = .zero

    init(onSelect: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onCancel = onCancel
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .cursorUpdate],
            owner: self
        ))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    // Top-left origin, matching ScreenCaptureKit's sourceRect.
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func mouseMoved(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        selection = .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = CGRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        ).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if selection.width >= 4, selection.height >= 4 {
            onSelect(selection)
        } else {
            onCancel()
        }
    }

    override func rightMouseDown(with event: NSEvent) { onCancel() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel() } // Esc
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        guard !selection.isEmpty else { return }
        NSColor.clear.setFill()
        selection.fill(using: .copy)
        NSColor.white.setStroke()
        NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }
}
