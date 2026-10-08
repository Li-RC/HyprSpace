// Adapted from Workspace Status. See legal/workspace-status/LICENSE.
import AppKit
import QuartzCore

let overviewShadowMargin: CGFloat = 32
let overviewTopMargin: CGFloat = 8

func overviewSize(visibleFrame: NSRect, anchor: NSRect, contentHeight: CGFloat = 240) -> NSSize {
    let width = max(1, min(360, visibleFrame.width - 2 * overviewShadowMargin - 28))
    let availableHeight = max(1, min(anchor.minY, visibleFrame.maxY) - visibleFrame.minY - overviewShadowMargin - 16)
    let scale = min(1, availableHeight / max(1, contentHeight))
    return NSSize(width: floor(width * scale), height: max(1, floor(contentHeight * scale)))
}

final class OverviewPanel: NSPanel {
    private(set) var isPresented = false
    private var transitionID = 0

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { dismiss() }

    func present() { transition(showing: true) }

    func dismiss() {
        guard isPresented else { return }
        transition(showing: false)
    }

    private func transition(showing: Bool) {
        let wasVisible = isVisible
        isPresented = showing
        transitionID += 1
        let id = transitionID
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : (showing ? 0.12 : 0.09)
        ignoresMouseEvents = !showing
        if showing {
            alphaValue = 1
            makeKeyAndOrderFront(nil)
            contentView?.layoutSubtreeIfNeeded()
        }
        if let view = contentView {
            view.wantsLayer = true
            if let layer = view.layer {
                let start = showing && !wasVisible ? 4 : (layer.presentation()?.transform.m42 ?? layer.transform.m42)
                let end: CGFloat = showing ? 0 : 4
                let startOpacity: Float = showing && !wasVisible ? 0 : (layer.presentation()?.opacity ?? layer.opacity)
                let endOpacity: Float = showing ? 1 : 0
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.transform = CATransform3DMakeTranslation(0, end, 0)
                layer.opacity = endOpacity
                CATransaction.commit()
                if duration > 0 {
                    let movement = CABasicAnimation(keyPath: "transform.translation.y")
                    movement.fromValue = start
                    movement.toValue = end
                    movement.duration = duration
                    movement.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    layer.add(movement, forKey: "dropdownMovement")
                    let fade = CABasicAnimation(keyPath: "opacity")
                    fade.fromValue = startOpacity
                    fade.toValue = endOpacity
                    fade.duration = duration
                    fade.timingFunction = movement.timingFunction
                    layer.add(fade, forKey: "dropdownFade")
                } else {
                    layer.removeAnimation(forKey: "dropdownMovement")
                    layer.removeAnimation(forKey: "dropdownFade")
                }
            }
        }
        if !showing {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                guard let self, self.transitionID == id, !self.isPresented else { return }
                self.orderOut(nil)
            }
        }
    }
}
