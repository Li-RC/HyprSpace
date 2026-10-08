// Adapted from Workspace Status. See legal/workspace-status/LICENSE.
import AppKit
import ApplicationServices

func menuStripFrame(screen: NSRect, hasNotch: Bool, native: NSRect?, menuEnd: CGFloat,
                    statusStart: CGFloat, width: CGFloat, workspaceWidth: CGFloat, height: CGFloat) -> NSRect? {
    if hasNotch { return native }
    let left = max(screen.minX, menuEnd + 8)
    let right = min(screen.maxX, statusStart - 8)
    guard width > 0, right > left else { return nil }
    // Center the drawn workspace group; still reserve space for the adjacent bell.
    let centered = screen.midX - workspaceWidth / 2 - MenuStripView.imageInset
    let fitsCenter = centered >= left && centered + width <= right
    return NSRect(x: fitsCenter ? centered : left, y: screen.maxY - height,
                  width: fitsCenter ? width : min(width, right - left), height: height)
}

@MainActor
final class MenuPlacement: ObservableObject {
    var automatic = true {
        didSet { if automatic != oldValue { refresh() } }
    }
    @Published private(set) var notice: String?
    private(set) var usesOverlays = false
    private(set) var menuWidth: CGFloat = 0
    var workspaceWidth: CGFloat = 0
    private(set) var statusStarts: [CGDirectDisplayID: CGFloat] = [:]
    private(set) var overlays: [CGDirectDisplayID: NSPanel] = [:]
    private weak var item: NSStatusItem?
    private var image: (() -> NSImage?)?
    private var click: ((NSPoint, TimeInterval) -> Void)?
    private var contextClick: ((NSPoint) -> Void)?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var loading = false
    private var started = false
    private var lastNativeFrame: NSRect?

    func start(item: NSStatusItem, image: @escaping () -> NSImage?, click: @escaping (NSPoint, TimeInterval) -> Void,
               contextClick: ((NSPoint) -> Void)? = nil) {
        self.item = item; self.image = image; self.click = click
        self.contextClick = contextClick
        started = true
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refresh() } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refresh() } })
        refresh()
    }

    func refresh() {
        guard automatic else {
            timer?.invalidate(); timer = nil
            restoreNative(); notice = nil
            return
        }
        guard started else { return }
        let screens = NSScreen.screens
        guard let item, screens.contains(where: { $0.auxiliaryTopLeftArea == nil }) else {
            timer?.invalidate(); timer = nil
            restoreNative(); notice = nil
            return
        }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        }
        guard AXIsProcessTrusted() else {
            restoreNative(); notice = "Enable Accessibility to position Workspace Status between application menus."
            return
        }
        guard !loading else { return }
        loading = true
        if let button = item.button, let window = unsafe button.window, item.isVisible {
            lastNativeFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        }
        let top = screens.first?.frame.maxY ?? 0
        let front = NSWorkspace.shared.menuBarOwningApplication
        let frontPID = front?.bundleIdentifier == "com.apple.loginwindow" ? nil : front?.processIdentifier
        let statusPIDs = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier == ProcessInfo.processInfo.processIdentifier ||
            ["com.apple.MenuBarAgent", "com.apple.systemuiserver", "com.apple.controlcenter"].contains($0.bundleIdentifier ?? "")
        }.map { (pid: $0.processIdentifier, bundle: $0.bundleIdentifier ?? "") }
        DispatchQueue.global(qos: .utility).async {
            let geometry = MenuGeometry.read(top: top, frontPID: frontPID, statusPIDs: statusPIDs)
            DispatchQueue.main.async {
                self.loading = false
                guard self.started, self.automatic, NSScreen.screens.contains(where: { $0.auxiliaryTopLeftArea == nil }) else { return }
                guard let geometry else {
                    self.restoreNative(); self.notice = "Application-menu positions are currently unavailable."
                    return
                }
                self.apply(geometry)
            }
        }
    }

    private func apply(_ geometry: MenuGeometry) {
        guard let item else { return }
        menuWidth = geometry.menuWidth
        let screens = NSScreen.screens
        var frames: [CGDirectDisplayID: NSRect] = [:]
        var starts: [CGDirectDisplayID: CGFloat] = [:]
        for screen in screens {
            let bounds = screen.frame
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let bar = geometry.bars.first(where: { abs($0.maxY - bounds.maxY) < 2 && $0.intersection(bounds).width > bounds.width * 0.8 }) else { continue }
            let menuEnd = bounds.minX + geometry.menuWidth
            let entries = geometry.statusItems.filter { $0.frame.intersects(bar) && $0.frame.width < bounds.width }
            let native = entries.first(where: \.own)?.frame ?? lastNativeFrame.flatMap { bounds.contains($0) ? $0 : nil }
            if screen.auxiliaryTopLeftArea != nil && native == nil {
                restoreNative(); notice = "The saved menu bar position is currently unavailable."
                return
            }
            // The native slot is a conservative boundary when other status items cannot be read.
            let statusStart = entries.filter { !$0.own && $0.frame.minX >= menuEnd }.map { $0.frame.minX }.min()
                ?? native?.minX
            starts[id] = statusStart
            guard screen.auxiliaryTopLeftArea != nil || statusStart != nil else {
                restoreNative(); notice = "Status icon positions are currently unavailable."
                return
            }
            if let frame = menuStripFrame(screen: bounds, hasNotch: screen.auxiliaryTopLeftArea != nil,
                native: native, menuEnd: menuEnd, statusStart: statusStart ?? bounds.maxX,
                width: item.length, workspaceWidth: workspaceWidth, height: bar.height) {
                if screen.auxiliaryTopLeftArea == nil || frame.minX >= menuEnd + 8 { frames[id] = frame }
            }
        }
        let hasNotch = screens.contains { $0.auxiliaryTopLeftArea != nil }
        statusStarts = starts
        display(frames: frames, reserveNativeSlot: hasNotch)
    }

    // Rendering also accepts fixture frames so external-display clicks can be checked on a laptop.
    func display(frames: [CGDirectDisplayID: NSRect], reserveNativeSlot: Bool) {
        guard let item, let image = image?() else { return }
        usesOverlays = true
        notice = nil
        item.button?.image = NSImage(size: image.size, flipped: false) { _ in true }
        item.isVisible = reserveNativeSlot
        for id in Array(overlays.keys) where frames[id] == nil {
            overlays.removeValue(forKey: id)?.close()
        }
        for (id, frame) in frames {
            let overlay: NSPanel
            if let existing = overlays[id] { overlay = existing }
            else {
                overlay = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                overlay.isOpaque = false; overlay.backgroundColor = .clear; overlay.hasShadow = false
                // Explicitly accept clear pixels; the default lets WindowServer pass those clicks through.
                overlay.ignoresMouseEvents = false
                overlay.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
                overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
                overlay.hidesOnDeactivate = false
                overlay.isReleasedWhenClosed = false
                let view = MenuStripView(frame: NSRect(origin: .zero, size: frame.size))
                view.autoresizingMask = [.width, .height]
                view.setAccessibilityElement(true)
                view.setAccessibilityRole(.button)
                view.setAccessibilityLabel("Workspace Status")
                view.click = click
                view.contextClick = contextClick
                overlay.contentView = view
                overlays[id] = overlay
            }
            let view = overlay.contentView as! MenuStripView
            view.setAccessibilityHelp(item.button?.toolTip)
            view.image = image; view.contentWidth = item.length
            view.appearance = item.button?.effectiveAppearance
            overlay.setFrame(frame, display: false)
            view.needsDisplay = true
            overlay.orderFrontRegardless()
        }
    }

    func overlay(at point: NSPoint) -> NSPanel? {
        overlays.values.first { $0.isVisible && $0.frame.contains(point) }
    }

    func updateImage() {
        guard let item, let image = image?() else { return }
        for overlay in overlays.values {
            let view = overlay.contentView as! MenuStripView
            view.setAccessibilityHelp(item.button?.toolTip)
            view.image = image; view.contentWidth = item.length
            view.needsDisplay = true
        }
    }

    private func restoreNative() {
        for overlay in overlays.values { overlay.orderOut(nil) }
        if usesOverlays {
            item?.button?.image = image?()
            item?.isVisible = true
        }
        usesOverlays = false
    }

    func stop() {
        started = false
        timer?.invalidate(); timer = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers = []
        restoreNative()
    }
}
