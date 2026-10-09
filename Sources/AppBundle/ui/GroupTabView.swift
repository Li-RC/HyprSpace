import AppKit

final class GroupTabView: NSView {
    var title = ""
    var selected = false
    var dragging = false
    var showsDivider = false

    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // The bar owns the entire drag, even while its child tabs slide underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        let tab = bounds.insetBy(dx: 4, dy: 4)
        guard tab.width > 0 else { return }
        if selected || dragging {
            let pill = NSBezierPath(roundedRect: tab, xRadius: tab.height / 2, yRadius: tab.height / 2)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.set()
            NSColor.windowBackgroundColor.withAlphaComponent(dragging ? 1 : 0.85).setFill()
            pill.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.labelColor.withAlphaComponent(0.10).setStroke()
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
            .font: NSFont.systemFont(ofSize: 13, weight: selected ? .medium : .regular),
            .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
        ]
        let textSize = (title as NSString).size(withAttributes: attributes)
        let textWidth = min(textSize.width, max(0, tab.width - 16))
        (title as NSString).draw(in: NSRect(x: tab.midX - textWidth / 2, y: tab.midY - textSize.height / 2,
                                          width: textWidth, height: textSize.height), withAttributes: attributes)
    }
}

// Use the same native tab/lens treatment as the Settings navigation bar.
final class GroupTabControl: NSSegmentedControl {
    private weak var owner: DecorationView?

    init(owner: DecorationView) {
        self.owner = owner
        super.init(frame: .zero)
        if #available(macOS 27.0, *) { role = .tabs }
        if #available(macOS 26.0, *) { borderShape = .capsule }
        segmentDistribution = .fill
        trackingMode = .selectOne
        font = .systemFont(ofSize: 13)
        focusRingType = .none
        target = self
        action = #selector(selectTab)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(labels: [String], selectedIndex: Int) {
        if segmentCount != labels.count { segmentCount = labels.count }
        for (index, label) in labels.enumerated() where self.label(forSegment: index) != label {
            setLabel(label, forSegment: index)
        }
        if selectedSegment != selectedIndex { selectedSegment = selectedIndex }
    }

    @objc private func selectTab() {
        guard let owner, owner.memberIds.indices.contains(selectedSegment) else { return }
        owner.selectTab(windowId: owner.memberIds[selectedSegment])
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { owner?.mouseDown(with: event) }
        else { super.mouseDown(with: event) }
    }

    override func mouseDragged(with event: NSEvent) { owner?.mouseDragged(with: event) }
    override func mouseUp(with event: NSEvent) { owner?.mouseUp(with: event) }
}
