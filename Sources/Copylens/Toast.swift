import AppKit

/// A short message near the bottom of the screen under the mouse.
enum Toast {
    private static var current: NSPanel?

    static func show(_ message: String, autoHide: Bool = true) {
        current?.orderOut(nil)

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.sizeToFit()

        let size = CGSize(width: label.frame.width + 36, height: label.frame.height + 20)
        label.setFrameOrigin(CGPoint(x: 18, y: 10))

        let background = NSView(frame: CGRect(origin: .zero, size: size))
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        background.layer?.cornerRadius = size.height / 2
        background.addSubview(label)

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let panel = NSPanel(
            contentRect: CGRect(
                origin: CGPoint(x: visible.midX - size.width / 2, y: visible.minY + 80),
                size: size
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = background
        panel.orderFrontRegardless()
        current = panel

        guard autoHide else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            guard current === panel else { return }
            panel.orderOut(nil)
            current = nil
        }
    }
}
