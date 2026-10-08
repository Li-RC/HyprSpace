// Adapted from Workspace Status. See legal/workspace-status/LICENSE.
import AppKit

final class MenuStripView: NSView {
    nonisolated static let imageInset: CGFloat = 2
    var image: NSImage?
    var contentWidth: CGFloat = 1
    var click: ((NSPoint, TimeInterval) -> Void)?
    var contextClick: ((NSPoint) -> Void)?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var scale: CGFloat { min(1, bounds.width / max(1, contentWidth)) }
    var contentOriginX: CGFloat { (bounds.width - contentWidth * scale) / 2 }
    var imageOriginX: CGFloat { contentOriginX + Self.imageInset * scale }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, scale > 0 else { return }
        image.draw(in: NSRect(x: imageOriginX, y: (bounds.height - 22 * scale) / 2,
                              width: image.size.width * scale, height: 22 * scale),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = unsafe self.window else { return }
        click?(window.convertPoint(toScreen: event.locationInWindow), event.timestamp)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let window = unsafe self.window else { return }
        contextClick?(window.convertPoint(toScreen: event.locationInWindow))
    }

    override func accessibilityPerformPress() -> Bool {
        guard let window = unsafe self.window, let click else { return false }
        click(NSPoint(x: window.frame.minX + imageOriginX + (contentWidth - 12) * scale, y: window.frame.midY),
              ProcessInfo.processInfo.systemUptime)
        return true
    }
}
