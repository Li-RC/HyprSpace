import AppKit

@MainActor
final class DwindleDropPreview {
    static let shared = DwindleDropPreview()
    private var panel: DecorationPanel?

    func hide() { panel?.orderOut(nil) }

    func show(_ rect: Rect?) {
        guard let rect else { hide(); return }
        let panel = panel ?? DecorationPanel()
        if self.panel == nil {
            self.panel = panel
            panel.contentView = DwindleDropPreviewView()
            panel.level = .floating
        }
        let view = panel.contentView as! DwindleDropPreviewView
        view.color = config.windowBorders.activeColor.nsColor
        panel.setFrame(decorationFrame(rect, primaryScreenHeight: mainMonitorInfo.height, borderWidth: 0, barHeight: 0), display: false)
        view.needsDisplay = true
        panel.orderFrontRegardless()
    }
}

private final class DwindleDropPreviewView: NSView {
    var color: NSColor = .systemBlue

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 16, yRadius: 16)
        color.withAlphaComponent(0.14).setFill()
        path.fill()
        color.withAlphaComponent(0.4).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}
