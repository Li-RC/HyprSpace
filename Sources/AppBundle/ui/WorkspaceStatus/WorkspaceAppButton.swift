// Adapted from Workspace Status. See legal/workspace-status/LICENSE.
import AppKit
import SwiftUI

final class AppClickButton: NSButton {
    var singleClick: (() -> Void)?
    var doubleClick: (() -> Void)?
    private var pendingClick: DispatchWorkItem?

    func handleMouseClick(count: Int) {
        pendingClick?.cancel()
        if count >= 2 { doubleClick?() }
        else {
            let click = DispatchWorkItem { [weak self] in self?.singleClick?() }
            pendingClick = click
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: click)
        }
    }

    @objc func activate() {
        if let event = NSApp.currentEvent, event.type == .leftMouseUp || event.type == .leftMouseDown {
            handleMouseClick(count: event.clickCount)
            return
        }
        pendingClick?.cancel()
        singleClick?()
    }

    isolated deinit { pendingClick?.cancel() }
}

struct WorkspaceAppButton: NSViewRepresentable {
    let bundle: String
    let name: String
    let current: Bool
    let space: String
    let singleClick: () -> Void
    let doubleClick: () -> Void

    func makeNSView(context: Context) -> AppClickButton {
        let button = AppClickButton()
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.focusRingType = .none
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.target = button
        button.action = #selector(AppClickButton.activate)
        return button
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AppClickButton, context: Context) -> CGSize? {
        CGSize(width: 20, height: 20)
    }

    func updateNSView(_ button: AppClickButton, context: Context) {
        button.image = appIcon(bundle)
        button.setAccessibilityLabel(name)
        button.toolTip = (current ? "Focus \(name)" : "Switch to workspace \(space)") + "; double-click to focus \(name)"
        button.singleClick = singleClick
        button.doubleClick = doubleClick
    }
}
