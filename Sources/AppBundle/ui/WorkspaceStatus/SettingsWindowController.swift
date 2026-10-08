// Adapted from Workspace Status. See legal/workspace-status/LICENSE.
import AppKit
import SwiftUI

// Fit to a connected display without changing a window's size on ordinary reopens.
func settingsWindowFrame(_ frame: NSRect, visibleFrame: NSRect) -> NSRect {
    let width = min(frame.width, visibleFrame.width), height = min(frame.height, visibleFrame.height)
    return NSRect(x: max(visibleFrame.minX, min(frame.minX, visibleFrame.maxX - width)),
                  y: max(visibleFrame.minY, min(frame.minY, visibleFrame.maxY - height)), width: width, height: height)
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let notifications: NotificationModel
    private var screenObserver: NSObjectProtocol?
    private var opened = false

    init(settings: SettingsStore, notifications: NotificationModel) {
        self.notifications = notifications
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 544, height: 384),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "HyprSpace Settings"
        window.isReleasedWhenClosed = false
        window.contentViewController = NoFocusOutlineHostingController(rootView: SettingsView(settings: settings, notifications: notifications))
        super.init(window: window)
        window.delegate = self
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.fitToScreen(preferred: nil) } }
    }

    required init?(coder: NSCoder) { fatalError("Settings windows are created programmatically") }

    func show(on screen: NSScreen?) {
        guard let window else { return }
        if !opened, let screen = screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: visible.midX - window.frame.width / 2,
                                          y: visible.midY - window.frame.height / 2))
        }
        opened = true
        fitToScreen(preferred: screen)
        notifications.checkPermission()
        if window.isMiniaturized { window.deminiaturize(nil) }
        // Settings is explicitly user-invoked, so bring it forward even while another app is active.
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    private func fitToScreen(preferred: NSScreen?) {
        guard let window else { return }
        let screens = NSScreen.screens
        let screen = screens.first { $0.visibleFrame.contains(window.frame) }
            ?? screens.max { $0.visibleFrame.intersection(window.frame).width * $0.visibleFrame.intersection(window.frame).height
                < $1.visibleFrame.intersection(window.frame).width * $1.visibleFrame.intersection(window.frame).height }
        let intersects = screen.map { $0.visibleFrame.intersects(window.frame) } ?? false
        guard let target = intersects ? screen : (preferred ?? NSScreen.main ?? screens.first) else { return }
        window.setFrame(settingsWindowFrame(window.frame, visibleFrame: target.visibleFrame), display: true)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        notifications.checkPermission()
    }

    isolated deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }
}
