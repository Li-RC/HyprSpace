import AppKit
import Common

let windowGroupBarHeight: CGFloat = 24

// Accessibility uses a top-left origin; AppKit uses a bottom-left origin.
func decorationFrame(_ rect: Rect, primaryScreenHeight: CGFloat, borderWidth: CGFloat, barHeight: CGFloat) -> NSRect {
    NSRect(x: rect.minX - borderWidth, y: primaryScreenHeight - rect.maxY - borderWidth,
           width: rect.width + borderWidth * 2, height: rect.height + borderWidth * 2 + barHeight)
}

final class DecorationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.transient, .fullScreenNone, .ignoresCycle]
        level = .normal
        contentView = DecorationView()
    }
}

func groupTabIndex(at point: CGPoint, in bounds: NSRect, memberCount: Int) -> Int? {
    guard memberCount > 0, bounds.width > 0, bounds.contains(point),
          point.y >= bounds.maxY - windowGroupBarHeight else { return nil }
    return min(memberCount - 1, Int((point.x - bounds.minX) / bounds.width * CGFloat(memberCount)))
}

@MainActor
func selectGroupTab(windowId: UInt32, in group: TilingContainer) -> Bool {
    guard group.isBound, group.isWindowGroup, let window = Window.get(byId: windowId),
          window.windowGroup === group else { return false }
    return window.focusWindow()
}

final class DecorationView: NSView {
    var borderWidth: CGFloat = 0
    var color: NSColor = .clear
    var members: [String] = []
    var activeIndex: Int = 0
    var memberIds: [UInt32] = []
    weak var group: TilingContainer?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {} // Keep keyboard focus in the member window.

    override func mouseUp(with event: NSEvent) {
        guard event.buttonNumber == 0, let group,
              let index = groupTabIndex(at: convert(event.locationInWindow, from: nil), in: bounds, memberCount: memberIds.count)
        else { return }
        let windowId = memberIds[index]
        Task.startUnstructured { @MainActor in
            guard let token: RunSessionGuard = .isServerEnabled else { return }
            try await runLightSession(.groupBar, token) {
                _ = selectGroupTab(windowId: windowId, in: group)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        let barHeight = members.isEmpty ? 0 : windowGroupBarHeight
        let body = NSRect(x: borderWidth / 2, y: borderWidth / 2,
                          width: bounds.width - borderWidth, height: bounds.height - barHeight - borderWidth)
        if borderWidth > 0 {
            color.setStroke()
            // AppKit on macOS 27 resolves standard window corners to 16 points.
            // The stroke sits outside the window, so its centerline needs half
            // the border width added to keep the inner edge concentric.
            let radius = 16 + borderWidth / 2
            let outline = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
            outline.lineWidth = borderWidth
            outline.stroke()
        }
        guard !members.isEmpty else { return }
        let tabWidth = bounds.width / CGFloat(members.count)
        for (index, title) in members.enumerated() {
            let tab = NSRect(x: CGFloat(index) * tabWidth, y: bounds.height - barHeight, width: tabWidth, height: barHeight)
            (index == activeIndex ? color : NSColor(srgbRed: 0.12, green: 0.13, blue: 0.18, alpha: 1)).setFill()
            tab.fill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            paragraph.alignment = .center
            let textColor: NSColor = .white
            (title as NSString).draw(in: tab.insetBy(dx: 5, dy: 4), withAttributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: textColor, .paragraphStyle: paragraph,
            ])
        }
    }
}

@MainActor
final class WindowDecorations {
    static let shared = WindowDecorations()
    private var panels: [UInt32: DecorationPanel] = [:]
    private var bars: [UInt32: DecorationPanel] = [:]
    func hideAll() {
        panels.values.forEach { $0.close() }
        panels.removeAll()
        bars.values.forEach { $0.close() }
        bars.removeAll()
    }

    func refresh() {
        if isUnitTest { return }
        guard TrayMenuModel.shared.isEnabled else { hideAll(); return }
        var visibleIds: Set<UInt32> = []
        var visibleBars: Set<UInt32> = []
        for workspace in Workspace.all where workspace.isVisible {
            for window in workspace.allLeafWindowsRecursive {
                guard                       window.isFloating || window.parent is TilingContainer,
                      !window.isInactiveGroupMember, !window.isFullscreen,
                      let rect = window.lastAppliedLayoutPhysicalRect else { continue }
                guard window.lastAppliedLayoutPhysicalRect != nil || currentlyManipulatedWithMouseWindowId == window.windowId else { continue }
                let color = (focus.windowOrNil == window ? config.windowBorders.activeColor : config.windowBorders.inactiveColor).nsColor
                let frame = decorationFrame(rect, primaryScreenHeight: mainMonitorInfo.height,
                                            borderWidth: CGFloat(config.windowBorders.width), barHeight: 0)
                if config.windowBorders.enabled {
                    visibleIds.insert(window.windowId)
                    let panel = panels[window.windowId] ?? DecorationPanel()
                    panels[window.windowId] = panel
                    let view = panel.contentView as! DecorationView
                    view.borderWidth = CGFloat(config.windowBorders.width)
                    view.color = color
                    panel.setFrame(frame, display: false)
                    view.needsDisplay = true
                    panel.order(.above, relativeTo: Int(window.windowId))
                }
                if let group = window.windowGroup {
                    visibleBars.insert(window.windowId)
                    let bar = bars[window.windowId] ?? DecorationPanel()
                    bars[window.windowId] = bar
                    // Only this narrow panel receives mouse events. The outline panel
                    // remains click-through, including the member's entire content area.
                    bar.ignoresMouseEvents = false
                    let view = bar.contentView as! DecorationView
                    view.group = group
                    view.color = color
                    view.members = group.children.enumerated().map { index, member in
                        "\(index + 1): \((member as! Window).app.name ?? "Window")"
                    }
                    view.memberIds = group.allLeafWindowsRecursive.map(\.windowId)
                    view.activeIndex = window.ownIndex ?? 0
                    bar.setFrame(NSRect(x: rect.minX, y: mainMonitorInfo.height - rect.minY,
                                        width: rect.width, height: windowGroupBarHeight), display: false)
                    view.needsDisplay = true
                    bar.order(.above, relativeTo: Int(window.windowId))
                }
            }
        }
        for id in Array(panels.keys) where !visibleIds.contains(id) { panels.removeValue(forKey: id)?.close() }
        for id in Array(bars.keys) where !visibleBars.contains(id) { bars.removeValue(forKey: id)?.close() }
    }
}
