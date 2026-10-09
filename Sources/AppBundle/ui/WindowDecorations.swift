import AppKit
import Common
import PrivateApi

let windowGroupBarHeight: CGFloat = 32
let windowGroupBarGap: CGFloat = 8

// Accessibility uses a top-left origin; AppKit uses a bottom-left origin.
func decorationFrame(_ rect: Rect, primaryScreenHeight: CGFloat, borderWidth: CGFloat, barHeight: CGFloat) -> NSRect {
    NSRect(x: rect.minX - borderWidth, y: primaryScreenHeight - rect.maxY - borderWidth,
           width: rect.width + borderWidth * 2, height: rect.height + borderWidth * 2 + barHeight)
}

func groupBarFrame(_ rect: Rect, primaryScreenHeight: CGFloat) -> NSRect {
    NSRect(x: rect.minX, y: primaryScreenHeight - rect.minY + windowGroupBarGap,
           width: rect.width, height: windowGroupBarHeight)
}

final class DecorationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func followOwner(_ rect: Rect, primaryScreenHeight: CGFloat, borderWidth: CGFloat, isGroupBar: Bool) {
        let frame = isGroupBar
            ? groupBarFrame(rect, primaryScreenHeight: primaryScreenHeight)
            : decorationFrame(rect, primaryScreenHeight: primaryScreenHeight, borderWidth: borderWidth, barHeight: 0)
        setFrame(frame, display: true)
    }

    func orderAboveOwner(_ owner: UInt32) {
        order(.above, relativeTo: Int(owner))
        // AppKit can assign panels sublevel 20 even at NSWindow.Level.normal.
        // Match the foreign owner's sublevel before applying relative ordering.
        if !HyprspaceOrderDecorationAboveWindow(UInt32(windowNumber), owner) {
            orderOut(nil)
        }
    }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        // Window capture selection must skip the decoration and select its owner.
        sharingType = .none
        hidesOnDeactivate = false
        collectionBehavior = [.transient, .fullScreenNone, .ignoresCycle]
        level = .normal
        contentView = DecorationView()
    }
}

func nativeDecorationOwnerRect(_ windowId: UInt32) -> Rect? {
    let bounds = HyprspaceDecorationOwnerBounds(windowId)
    guard !bounds.isNull else { return nil }
    return Rect(topLeftX: bounds.minX, topLeftY: bounds.minY, width: bounds.width, height: bounds.height)
}

func onScreenDecorationOwners(_ windowInfo: [[String: Any]]) -> Set<UInt32> {
    Set(windowInfo.compactMap { info in
        guard (info[kCGWindowIsOnscreen as String] as? Bool) == true else { return nil }
        return (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
    })
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

final class GroupBarView: NSView {
    let tabs = DecorationView()
    let background: NSView

    init() {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = windowGroupBarHeight / 2
            if #available(macOS 27.0, *) { glass.effectIsInteractive = true }
            background = glass
        } else {
            let material = NSVisualEffectView()
            material.material = .popover
            material.blendingMode = .behindWindow
            material.wantsLayer = true
            material.layer?.cornerRadius = windowGroupBarHeight / 2
            material.layer?.masksToBounds = true
            background = material
        }
        super.init(frame: .zero)
        background.autoresizingMask = [.width, .height]
        tabs.autoresizingMask = [.width, .height]
        addSubview(background)
        if #available(macOS 26.0, *), let glass = background as? NSGlassEffectView {
            glass.contentView = tabs
        } else {
            background.addSubview(tabs)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        background.frame = bounds
        tabs.frame = background.bounds
    }
}

struct GroupTabDrag {
    let windowId: UInt32
    let origin: CGPoint
    let originalIndex: Int
    var isDragging = false
    var targetIndex: Int?

    mutating func update(at point: CGPoint, in bounds: NSRect, memberCount: Int) {
        if max(abs(point.x - origin.x), abs(point.y - origin.y)) >= 4 { isDragging = true }
        targetIndex = isDragging ? groupTabIndex(at: point, in: bounds, memberCount: memberCount) : nil
    }

    @MainActor @discardableResult
    func apply(in group: TilingContainer) -> Bool {
        guard isDragging, let targetIndex else { return false }
        return group.reorderWindowGroupMember(windowId, to: targetIndex)
    }

    @MainActor @discardableResult
    func cancel(in group: TilingContainer) -> Bool {
        guard isDragging else { return false }
        return group.reorderWindowGroupMember(windowId, to: min(originalIndex, group.children.count - 1))
    }
}

final class DecorationView: NSView {
    var borderWidth: CGFloat = 0
    var color: NSColor = .clear
    var members: [String] = []
    var activeIndex: Int = 0
    var memberIds: [UInt32] = []
    weak var group: TilingContainer?
    private var tabDrag: GroupTabDrag?

    func updateGroup(_ group: TilingContainer) {
        self.group = group
        members = group.allLeafWindowsRecursive.map { $0.app.name ?? "Window" }
        memberIds = group.allLeafWindowsRecursive.map(\.windowId)
        activeIndex = group.mostRecentWindowRecursive?.ownIndex ?? 0
        needsDisplay = true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard event.buttonNumber == 0,
              let index = groupTabIndex(at: point, in: bounds, memberCount: memberIds.count) else { return }
        // Keep keyboard focus in the member window until a click is completed.
        tabDrag = GroupTabDrag(windowId: memberIds[index], origin: point, originalIndex: index)
    }

    override func mouseDragged(with event: NSEvent) {
        guard var drag = tabDrag else { return }
        drag.update(at: convert(event.locationInWindow, from: nil), in: bounds, memberCount: memberIds.count)
        tabDrag = drag
        if TrayMenuModel.shared.isEnabled, let group {
            _ = drag.apply(in: group)
            updateGroup(group)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { tabDrag = nil; needsDisplay = true }
        guard event.buttonNumber == 0, let group, var drag = tabDrag else { return }
        let point = convert(event.locationInWindow, from: nil)
        drag.update(at: point, in: bounds, memberCount: memberIds.count)
        if drag.isDragging {
            if drag.targetIndex != nil { _ = drag.apply(in: group) } else { _ = drag.cancel(in: group) }
            updateGroup(group)
            WindowDecorations.shared.refresh()
            return
        }
        guard let index = groupTabIndex(at: point, in: bounds, memberCount: memberIds.count),
              memberIds[index] == drag.windowId else { return }
        Task.startUnstructured { @MainActor in
            guard let token: RunSessionGuard = .isServerEnabled else { return }
            try await runLightSession(.groupBar, token) {
                _ = selectGroupTab(windowId: drag.windowId, in: group)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        if !members.isEmpty {
            drawGroupTabs()
            return
        }
        let body = NSRect(x: borderWidth / 2, y: borderWidth / 2,
                          width: bounds.width - borderWidth, height: bounds.height - borderWidth)
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
    }

    private func drawGroupTabs() {
        let tabWidth = bounds.width / CGFloat(members.count)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        for (index, title) in members.enumerated() {
            let tab = NSRect(x: bounds.minX + CGFloat(index) * tabWidth, y: bounds.maxY - windowGroupBarHeight,
                             width: tabWidth, height: windowGroupBarHeight).insetBy(dx: 4, dy: 4)
            guard tab.width > 0 else { continue }
            let selected = index == activeIndex
            if selected {
                let pill = NSBezierPath(roundedRect: tab, xRadius: tab.height / 2, yRadius: tab.height / 2)
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
                shadow.shadowBlurRadius = 2
                shadow.shadowOffset = NSSize(width: 0, height: -1)
                shadow.set()
                NSColor.windowBackgroundColor.withAlphaComponent(0.85).setFill()
                pill.fill()
                NSGraphicsContext.restoreGraphicsState()
                NSColor.labelColor.withAlphaComponent(0.10).setStroke()
                pill.lineWidth = 0.5
                pill.stroke()
            } else if index > 0 && index - 1 != activeIndex {
                NSColor.labelColor.withAlphaComponent(0.12).setStroke()
                let divider = NSBezierPath()
                divider.move(to: CGPoint(x: tab.minX - 4, y: tab.minY + 4))
                divider.line(to: CGPoint(x: tab.minX - 4, y: tab.maxY - 4))
                divider.lineWidth = 0.5
                divider.stroke()
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: selected ? .medium : .regular),
                .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
            ]
            let textSize = (title as NSString).size(withAttributes: attributes)
            let textWidth = min(textSize.width, max(0, tab.width - 16))
            (title as NSString).draw(in: NSRect(x: tab.midX - textWidth / 2, y: tab.midY - textSize.height / 2,
                                               width: textWidth, height: textSize.height),
                                    withAttributes: attributes)
        }

    }
}

@MainActor
final class WindowDecorations {
    static let shared = WindowDecorations()
    private var panels: [UInt32: DecorationPanel] = [:]
    private var bars: [UInt32: DecorationPanel] = [:]
    private var observedOwners: Set<UInt32> = []
    private var ownerFrames: [UInt32: Rect] = [:]

    private func updateObservedOwners(_ owners: Set<UInt32>) {
        guard owners != observedOwners else { return }
        let ids = Array(owners)
        let subscribed = ids.withUnsafeBufferPointer { buffer in
            unsafe HyprspaceObserveDecorationWindows(buffer.baseAddress, Int32(buffer.count)) { windowId, event in
                MainActor.assumeIsolated {
                    WindowDecorations.shared.ownerChanged(windowId: windowId, event: event)
                }
            }
        }
        if subscribed { observedOwners = owners }
    }

    func captureMouseDrag(windowId: UInt32) {
        guard observedOwners.contains(windowId), let previous = ownerFrames[windowId],
              let rect = nativeDecorationOwnerRect(windowId), let window = Window.get(byId: windowId),
              focus.windowOrNil == window || window.app.pid == NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        recordDwindleMouseMove(window, from: previous, to: rect, mouseButtonDown: isLeftMouseButtonDown)
    }

    func ownerChanged(windowId: UInt32, event: UInt32) {
        guard observedOwners.contains(windowId) else { return }
        if event == 804 || event == 816 {
            panels.removeValue(forKey: windowId)?.close()
            bars.removeValue(forKey: windowId)?.close()
            ownerFrames.removeValue(forKey: windowId)
            updateObservedOwners(observedOwners.subtracting([windowId]))
            return
        }
        guard let rect = nativeDecorationOwnerRect(windowId) else { return }
        if event == 806 {
            captureMouseDrag(windowId: windowId)
            if config.enableDwindleTiling { updateDwindleDragPreview(at: mouseLocation) }
        }
        ownerFrames[windowId] = rect
        if let panel = panels[windowId] {
            panel.followOwner(rect, primaryScreenHeight: mainMonitorInfo.height,
                              borderWidth: CGFloat(config.windowBorders.width), isGroupBar: false)
        }
        if let bar = bars[windowId] {
            bar.followOwner(rect, primaryScreenHeight: mainMonitorInfo.height, borderWidth: 0, isGroupBar: true)
        }
    }

    func hideAll() {
        DwindleDropPreview.shared.hide()
        panels.values.forEach { $0.close() }
        panels.removeAll()
        bars.values.forEach { $0.close() }
        bars.removeAll()
        ownerFrames.removeAll()
        updateObservedOwners([])
    }

    func refresh() {
        if isUnitTest { return }
        guard TrayMenuModel.shared.isEnabled else { hideAll(); return }
        // A HyprSpace workspace can remain visible in our model while macOS
        // switches to a native fullscreen Space. Consult WindowServer as well.
        let onScreenOwners = onScreenDecorationOwners(
            CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0) as? [[String: Any]] ?? [],
        )
        var visibleIds: Set<UInt32> = []
        var visibleBars: Set<UInt32> = []
        var trackingOwners: Set<UInt32> = []
        for workspace in Workspace.all where workspace.isVisible {
            for window in workspace.allLeafWindowsRecursive {
                guard onScreenOwners.contains(window.windowId),
                      window.isFloating || window.parent is TilingContainer,
                      !window.isInactiveGroupMember, !window.isFullscreen,
                      let rect = nativeDecorationOwnerRect(window.windowId) else { continue }
                trackingOwners.insert(window.windowId)
                ownerFrames[window.windowId] = rect
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
                    panel.orderAboveOwner(window.windowId)
                }
                if let group = window.windowGroup {
                    visibleBars.insert(window.windowId)
                    let bar: DecorationPanel
                    if let existing = bars[window.windowId] {
                        bar = existing
                    } else {
                        bar = DecorationPanel()
                        bar.contentView = GroupBarView()
                        bars[window.windowId] = bar
                    }
                    // Only this narrow panel receives mouse events. The outline panel
                    // remains click-through, including the member's entire content area.
                    bar.ignoresMouseEvents = false
                    let material = bar.contentView as! GroupBarView
                    if let fallback = material.background as? NSVisualEffectView {
                        fallback.state = focus.windowOrNil?.windowGroup === group ? .active : .inactive
                    }
                    let view = material.tabs
                    view.updateGroup(group)
                    bar.setFrame(groupBarFrame(rect, primaryScreenHeight: mainMonitorInfo.height), display: false)
                    view.needsDisplay = true
                    bar.orderAboveOwner(window.windowId)
                }
            }
        }
        for id in Array(panels.keys) where !visibleIds.contains(id) { panels.removeValue(forKey: id)?.close() }
        for id in Array(bars.keys) where !visibleBars.contains(id) { bars.removeValue(forKey: id)?.close() }
        ownerFrames = ownerFrames.filter { trackingOwners.contains($0.key) }
        updateObservedOwners(trackingOwners)
    }
}
