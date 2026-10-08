// Adapted from Workspace Status. See legal/workspace-status/LICENSE.
import AppKit
import SwiftUI
import Common
import Combine

@MainActor
final class WorkspaceStatusController: NSObject {
    static let shared = WorkspaceStatusController()
    let settings: SettingsStore
    lazy var settingsWindow = SettingsWindowController(settings: settings, notifications: notifications)
    let workspaces = WorkspaceModel.shared
    let notifications = NotificationModel()
    let overviewState = OverviewState()
    let placement = MenuPlacement()
    private(set) var statusImage: NSImage?
    private var overviewAnchor: (rect: NSRect, screen: NSScreen, centerX: CGFloat)?
    private(set) var naturalHeight: CGFloat = 240
    var item: NSStatusItem!
    private(set) var workspaceFrames: [String: NSRect] = [:]
    private(set) var appFrames: [String: [String: NSRect]] = [:]
    private(set) var bellFrame = NSRect.zero
    private var trayObservation: AnyCancellable?
    private var appearanceObservation: NSKeyValueObservation?
    private(set) var menuOrder: [String] = []
    let panel = OverviewPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var hosting: NSHostingController<Overview>!
    private var lastAppClick: (space: String, bundle: String, point: NSPoint, timestamp: TimeInterval)?

    init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        super.init()
    }

    func start() {
        guard item == nil else { return }
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        placement.automatic = settings.menuBarPosition == .automatic
        settings.changed = { [weak self] in self?.applySettings() }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(menuBarClicked(_:))
        item.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        item.button?.imagePosition = .imageLeft
        item.button?.attributedTitle = NSAttributedString(string: "")
        item.button?.imageHugsTitle = true
        item.button?.setAccessibilityLabel("HyprSpace Workspace Status")
        appearanceObservation = item.button?.observe(\.effectiveAppearance, options: [.old, .new]) { [weak self] _, change in
            guard change.oldValue?.name != change.newValue?.name else { return }
            Task { @MainActor in self?.updateStatus() }
        }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissIfOutside(at: NSEvent.mouseLocation)
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let point = event.window === (unsafe self?.item.button?.window) ? NSEvent.mouseLocation :
                (event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation)
            self?.dismissIfOutside(at: point)
            return event
        }
        hosting = NSHostingController(rootView:
            Overview(workspaces: workspaces, notifications: notifications, placement: placement,
                     close: { [weak self] in self?.panel.dismiss() }, state: overviewState,
                     resized: { [weak self] height in self?.resizeOverview(to: height) },
                     openSettings: { [weak self] in self?.showSettings(nil) }))
        hosting.sizingOptions = []
        let container = NSViewController()
        container.addChild(hosting)
        let backdrop = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 560))
        backdrop.addSubview(hosting.view)
        hosting.view.clipsToBounds = false
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor, constant: overviewShadowMargin),
            hosting.view.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor, constant: -overviewShadowMargin),
            hosting.view.topAnchor.constraint(equalTo: backdrop.topAnchor, constant: overviewTopMargin),
            hosting.view.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor, constant: -overviewShadowMargin)
        ])
        container.view = backdrop
        panel.contentViewController = container
        workspaces.changed = { [weak self] in self?.updateStatus() }
        notifications.changed = { [weak self] in self?.updateStatus() }
        let tray = TrayMenuModel.shared
        trayObservation = Publishers.CombineLatest3(tray.$isEnabled, tray.$axPermissionStatus, tray.$lastReloadConfigContainedWarnings)
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 }
            .sink { [weak self] _ in
            Task { @MainActor in self?.updateStatus() }
        }
        updateStatus()
        workspaces.updateFromTree()
        notifications.setMonitoring(settings.dockBadgesEnabled)
        notifications.start()
        placement.start(item: item, image: { [weak self] in self?.statusImage },
            click: { [weak self] point, time in self?.clickMenuBar(at: point, timestamp: time) },
            contextClick: { [weak self] point in self?.showBellContextMenu(at: point) })
    }

    private func installMainMenu() {
        let menu = NSMenu()
        let appMenu = NSMenu(title: "HyprSpace Workspace Status")
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        let quitItem = appMenu.addItem(withTitle: "Quit HyprSpace", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApp.mainMenu = menu
    }

    private func applySettings() {
        lastAppClick = nil
        placement.automatic = settings.menuBarPosition == .automatic
        notifications.setMonitoring(settings.dockBadgesEnabled)
        updateStatus()
    }

    @objc func showSettings(_ sender: Any?) {
        let point = ((sender as? NSMenuItem)?.representedObject as? NSValue)?.pointValue ?? NSEvent.mouseLocation
        let screen = panel.isPresented ? popupAnchor()?.1 : NSScreen.screens.first { $0.frame.contains(point) }
        panel.dismiss()
        // Release the nonactivating panel's key window before requesting settings activation.
        panel.orderOut(nil)
        lastAppClick = nil
        settingsWindow.show(on: screen)
    }

    func bellContextMenu(at point: NSPoint) -> NSMenu? {
        guard menuPoint(at: point) != nil else { return nil }
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: "")
        settingsItem.target = self
        settingsItem.representedObject = NSValue(point: point)
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let model = TrayMenuModel.shared
        if model.axPermissionStatus != .granted {
            addControl(to: menu, title: "Grant Accessibility permission…", action: #selector(requestAccessibility(_:)))
        }
        addControl(to: menu, title: model.isEnabled ? "Disable HyprSpace" : "Enable HyprSpace", action: #selector(toggleEnabled(_:)))
        addControl(to: menu, title: model.lastReloadConfigContainedWarnings ? "Reload config (contains warnings)" : "Reload config", action: #selector(reloadConfig(_:)))
        addControl(to: menu, title: "Open config…", action: #selector(openConfig(_:)))
        menu.addItem(.separator())
        let quitItem = menu.addItem(withTitle: "Quit HyprSpace", action: #selector(quit(_:)), keyEquivalent: "")
        quitItem.target = self
        return menu
    }

    private func addControl(to menu: NSMenu, title: String, action: Selector) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
    }

    @objc func requestAccessibility(_ sender: Any?) {
        TrayMenuModel.shared.axPermissionStatus = .waitingWithPrompt
        notifications.enable()
    }

    @objc func toggleEnabled(_ sender: Any?) {
        workspaces.perform(["enable", "toggle"], completion: {})
    }

    @objc func reloadConfig(_ sender: Any?) {
        workspaces.perform(["reload-config"], completion: {})
    }

    @objc func openConfig(_ sender: Any?) {
        let destination = FileManager.default.homeDirectoryForCurrentUser.appending(path: configDotfileName)
        let url: URL
        switch findCustomConfigUrl() {
            case .file(let existing): url = existing
            case .noCustomConfigExists:
                if !FileManager.default.fileExists(atPath: destination.path) {
                    try? FileManager.default.copyItem(at: defaultConfigUrl, to: destination)
                }
                url = destination
            case .ambiguousConfigError: url = destination
        }
        url.open(with: getTextEditorToOpenConfig())
    }

    @objc func quit(_ sender: Any?) {
        terminationHandler?.beforeTermination()
        terminateApp()
    }

    func showBellContextMenu(at point: NSPoint) {
        guard let menu = bellContextMenu(at: point) else { return }
        panel.dismiss()
        lastAppClick = nil
        menu.popUp(positioning: nil, at: point, in: nil)
    }

    func updateStatus() {
        guard item != nil else { return }
        let snapshot = workspaces.snapshot
        let tray = TrayMenuModel.shared
        let statusBadge = tray.axPermissionStatus != .granted ? "!" : (!tray.isEnabled ? "Ⅱ" : nil)
        let compact = settings.compactViewEnabled
        item.button?.toolTip = compact ? "HyprSpace Workspace Status: click a workspace to switch or the bell for overview."
            : "HyprSpace Workspace Status: click a workspace to switch, an app in the current workspace to focus, or the bell for overview. Double-click any app to focus it."
        menuOrder = snapshot.menuSpaces
        workspaceFrames = [:]
        appFrames = [:]
        var x: CGFloat = 0
        for space in menuOrder {
            let badge = workspaceBadge(space == snapshot.current ? (statusBadge ?? space) : space)
            let bundles = compact ? [] : snapshot.appBundles(in: space)
            let width = badge.size.width + (bundles.isEmpty ? 0 : CGFloat(bundles.count * 21 + 4) + 2) + 4
            workspaceFrames[space] = NSRect(x: x, y: 0, width: width, height: 22)
            appFrames[space] = Dictionary(uniqueKeysWithValues: bundles.enumerated().map { index, bundle in
                (bundle, NSRect(x: x + badge.size.width + 6 + CGFloat(index * 21), y: 0, width: 16, height: 22))
            })
            x += width
        }
        bellFrame = NSRect(x: x, y: 0, width: 24, height: 22)
        placement.workspaceWidth = x
        let hasBadges = !notifications.badges.isEmpty
        let bell = NSImage(systemSymbolName: hasBadges ? "bell.badge.fill" : "bell", accessibilityDescription: nil)!
        let bellImage = hasBadges ? bell.withSymbolConfiguration(.init(paletteColors: [.systemOrange]))! : bell
        bellImage.isTemplate = !hasBadges
        let frames = workspaceFrames
        let bellRect = bellFrame
        // Share the same strip and hit regions between the native item and positioned displays.
        statusImage = NSImage(size: NSSize(width: x + 20, height: 22), flipped: true) { [weak self] _ in
            guard let button = self?.item.button else { return false }
            @MainActor func drawSymbol(_ image: NSImage, in frame: NSRect) {
                if self?.placement.usesOverlays == true {
                    menuBarSymbol(image).draw(in: frame,
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                } else {
                    (button.cell as! NSButtonCell).drawImage(image, withFrame: frame, in: button)
                }
            }
            for space in snapshot.menuSpaces {
                let frame = frames[space]!
                let current = space == snapshot.current
                let badge = workspaceBadge(current ? (statusBadge ?? (self?.workspaces.error != nil ? "!" : space)) : space, selected: current)
                drawSymbol(badge, in: NSRect(origin: frame.origin, size: badge.size))
                let bundles = compact ? [] : snapshot.appBundles(in: space)
                if !bundles.isEmpty {
                    let icons = iconStrip(bundles)
                    icons.draw(in: NSRect(x: frame.minX + badge.size.width + 2, y: 0, width: icons.size.width, height: 22),
                               from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
            }
            let size = bellImage.size
            let frame = NSRect(x: bellRect.midX - size.width / 2 - 2, y: (22 - size.height) / 2,
                               width: size.width, height: size.height)
            drawSymbol(bellImage, in: frame)
            return true
        }
        if let statusImage {
            item.button?.image = placement.usesOverlays
                ? NSImage(size: statusImage.size, flipped: false) { _ in true } : statusImage
        }
        item.length = x + 24
        placement.updateImage()
        placement.refresh()
    }

    private func workspaceTarget(at imagePoint: NSPoint) -> (space: String, bundle: String?)? {
        guard let space = menuOrder.first(where: { workspaceFrames[$0]!.contains(imagePoint) }) else { return nil }
        let bundle = appFrames[space]?.first(where: { $0.value.contains(imagePoint) })?.key
        return (space, bundle)
    }

    // Convert both renderers to the image coordinates used by every click target.
    private func menuPoint(at screenPoint: NSPoint) -> NSPoint? {
        if let overlay = placement.overlay(at: screenPoint), let view = overlay.contentView as? MenuStripView, view.scale > 0 {
            return NSPoint(x: (screenPoint.x - overlay.frame.minX - view.imageOriginX) / view.scale, y: 11)
        }
        guard !placement.usesOverlays, let button = item.button, let window = unsafe button.window,
              window.frame.contains(screenPoint) else { return nil }
        let location = button.convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        let inset = button.cell!.imageRect(forBounds: button.bounds).minX
        return NSPoint(x: location.x - inset, y: 11)
    }

    func menuNavigation(at screenPoint: NSPoint, timestamp: TimeInterval) -> (workspaceClick: Bool, arguments: [String]?) {
        let previous = lastAppClick
        lastAppClick = nil
        if let previous, timestamp > previous.timestamp,
           timestamp - previous.timestamp <= NSEvent.doubleClickInterval,
           abs(screenPoint.x - previous.point.x) <= 4, abs(screenPoint.y - previous.point.y) <= 4 {
            // Keep the first app target even if switching rearranges the menu bar.
            return (true, workspaces.navigationArguments(to: previous.space, appBundle: previous.bundle, focusApp: true))
        }
        guard let location = menuPoint(at: screenPoint),
              let target = workspaceTarget(at: location) else { return (false, nil) }
        if let bundle = target.bundle { lastAppClick = (target.space, bundle, screenPoint, timestamp) }
        return (true, workspaces.navigationArguments(to: target.space, appBundle: target.bundle))
    }

    @objc func menuBarClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseDown {
            showBellContextMenu(at: NSEvent.mouseLocation)
        } else if let event = NSApp.currentEvent, event.type == .leftMouseDown {
            // macOS's menu bar host forwards mouse events at the item's center.
            clickMenuBar(at: NSEvent.mouseLocation, timestamp: event.timestamp)
        } else {
            overviewAnchor = nil
            toggle()
        }
    }

    func clickMenuBar(at screenPoint: NSPoint, timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let navigation = menuNavigation(at: screenPoint, timestamp: timestamp)
        if navigation.workspaceClick {
            panel.dismiss()
            if let arguments = navigation.arguments { workspaces.perform(arguments, completion: {}) }
            return
        }
        guard let location = menuPoint(at: screenPoint), bellFrame.contains(location) else { return }
        if let overlay = placement.overlay(at: screenPoint), let screen = overlay.screen,
           let view = overlay.contentView as? MenuStripView {
            let bell = NSRect(x: overlay.frame.minX + view.imageOriginX + bellFrame.minX * view.scale,
                y: overlay.frame.midY - 11 * view.scale, width: bellFrame.width * view.scale, height: 22 * view.scale)
            let workspaceCenter = overlay.frame.minX + view.imageOriginX + bellFrame.minX * view.scale / 2
            let centerX = abs(workspaceCenter - screen.frame.midX) < 1 ? screen.frame.midX : bell.midX
            overviewAnchor = (bell, screen, centerX)
        } else { overviewAnchor = nil }
        toggle()
    }

    @objc func toggle() {
        lastAppClick = nil
        showOverview()
    }

    func dismissIfOutside(at point: NSPoint) {
        guard panel.isPresented else { return }
        let contentFrame = panel.convertToScreen(hosting.view.convert(hosting.view.bounds, to: nil))
        guard !contentFrame.contains(point) else { return }
        if let location = menuPoint(at: point), bellFrame.contains(location) { return }
        if let button = item.button, let window = unsafe button.window {
            let inset = button.cell!.imageRect(forBounds: button.bounds).minX
            let bell = window.convertToScreen(button.convert(bellFrame.offsetBy(dx: inset, dy: 0), to: nil))
            if point.y >= window.frame.minY, point.y <= window.frame.maxY,
               point.x >= bell.minX, point.x <= bell.maxX { return }
        }
        panel.dismiss()
    }

    private func showOverview() {
        if panel.isPresented { panel.dismiss(); return }
        guard let (anchor, screen, centerX) = popupAnchor() else { return }
        hosting.rootView.width = max(1, min(360, screen.visibleFrame.width - 2 * overviewShadowMargin - 28))
        fitOverview(visibleFrame: screen.visibleFrame, anchor: anchor, centerX: centerX)
        workspaces.refresh()
        panel.present()
    }

    private func resizeOverview(to height: CGFloat) {
        guard height > 0, abs(naturalHeight - height) > 0.5 else { return }
        naturalHeight = height
        guard panel.isPresented, let (anchor, screen, centerX) = popupAnchor() else { return }
        fitOverview(visibleFrame: screen.visibleFrame, anchor: anchor, centerX: centerX)
    }

    private func popupAnchor() -> (NSRect, NSScreen, CGFloat)? {
        if let overviewAnchor { return (overviewAnchor.rect, overviewAnchor.screen, overviewAnchor.centerX) }
        guard let button = item.button, let window = unsafe button.window, let screen = window.screen else { return nil }
        let inset = button.cell!.imageRect(forBounds: button.bounds).minX
        let bell = window.convertToScreen(button.convert(bellFrame.offsetBy(dx: inset, dy: 0), to: nil))
        return (bell, screen, bell.midX)
    }

    private func fitOverview(visibleFrame: NSRect, anchor: NSRect, centerX: CGFloat) {
        let size = overviewSize(visibleFrame: visibleFrame, anchor: anchor, contentHeight: naturalHeight)
        hosting.rootView.canvasHeight = naturalHeight
        hosting.rootView.scale = size.height / naturalHeight
        let top = min(anchor.minY - 8, visibleFrame.maxY - 8)
        let panelSize = NSSize(width: size.width + 2 * overviewShadowMargin,
                              height: size.height + overviewTopMargin + overviewShadowMargin)
        let origin = NSPoint(x: max(visibleFrame.minX,
            min(centerX - panelSize.width / 2, visibleFrame.maxX - panelSize.width)),
            y: top - size.height - overviewShadowMargin)
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    func stop() {
        guard item != nil else { return }
        workspaces.changed = nil
        notifications.changed = nil
        settings.changed = nil
        appearanceObservation = nil
        trayObservation = nil
        panel.dismiss()
        workspaces.stop(); notifications.stop()
        placement.stop()
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        outsideClickMonitor = nil
        localClickMonitor = nil
        NSStatusBar.system.removeStatusItem(item)
        item = nil
    }
}
