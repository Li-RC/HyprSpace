import AppKit

final class GroupTabView: NSView {
    var title = "" { didSet { updateTab() } }
    var selected = false { didSet { updateTab() } }
    var dragging = false { didSet { updateTab() } }
    var showsDivider = false
    var onSelect: (() -> Void)?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
    }

    private func updateTab() {
        setAccessibilityLabel(title)
        setAccessibilityValue(selected)
        needsDisplay = true
    }

    override func accessibilityPerformPress() -> Bool {
        guard let onSelect else { return false }
        onSelect()
        return true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // The bar owns the entire drag, even while its child tabs slide underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        let tab = bounds.insetBy(dx: 4, dy: 4)
        guard tab.width > 0 else { return }
        let textColor: NSColor = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .white : .black
        if selected || dragging {
            let pill = NSBezierPath(roundedRect: tab, xRadius: tab.height / 2, yRadius: tab.height / 2)
            textColor.withAlphaComponent(dragging ? 0.22 : 0.12).setFill()
            pill.fill()
            textColor.withAlphaComponent(0.16).setStroke()
            pill.lineWidth = 0.5
            pill.stroke()
        } else if showsDivider {
            NSColor.labelColor.withAlphaComponent(0.12).setStroke()
            let divider = NSBezierPath()
            divider.move(to: CGPoint(x: 0.5, y: tab.minY + 4))
            divider.line(to: CGPoint(x: 0.5, y: tab.maxY - 4))
            divider.lineWidth = 0.5
            divider.stroke()
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: selected ? .semibold : .medium),
            .foregroundColor: textColor, .paragraphStyle: paragraph,
        ]
        let textSize = (title as NSString).size(withAttributes: attributes)
        let textWidth = min(textSize.width, max(0, tab.width - 16))
        (title as NSString).draw(in: NSRect(x: tab.midX - textWidth / 2, y: tab.midY - textSize.height / 2,
                                          width: textWidth, height: textSize.height), withAttributes: attributes)
    }
}
