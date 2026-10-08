// Adapted from Workspace Status. See legal/workspace-status/LICENSE.
import AppKit
import ApplicationServices

private func accessibilityFrame(_ element: AXUIElement, top: CGFloat) -> NSRect? {
    guard let p = axValue(element, kAXPositionAttribute), let s = axValue(element, kAXSizeAttribute),
          CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero, size = CGSize.zero
    guard unsafe AXValueGetValue(p as! AXValue, .cgPoint, &point), unsafe AXValueGetValue(s as! AXValue, .cgSize, &size),
          size.width > 0, size.height > 0 else { return nil }
    return NSRect(x: point.x, y: top - point.y - size.height, width: size.width, height: size.height)
}

private func isWorkspaceStatus(_ element: AXUIElement, depth: Int = 2) -> Bool {
    if [kAXTitleAttribute, kAXDescriptionAttribute].contains(where: {
        (axValue(element, $0) as? String)?.contains("HyprSpace Workspace Status") == true
    }) { return true }
    return depth > 0 && axChildren(element).contains { isWorkspaceStatus($0, depth: depth - 1) }
}

struct MenuGeometry {
    var menuWidth: CGFloat
    var bars: [NSRect]
    var statusItems: [(frame: NSRect, own: Bool)]

    static func read(top: CGFloat, frontPID: pid_t?, statusPIDs: [(pid: pid_t, bundle: String)]) -> MenuGeometry? {
        // Accessory apps can receive keyboard focus while another app still owns the visible menus.
        guard let frontPID else { return nil }
        let application = AXUIElementCreateApplication(frontPID)
        AXUIElementSetMessagingTimeout(application, 0.15)
        var menu: CFTypeRef?
        let error = unsafe AXUIElementCopyAttributeValue(application, kAXMenuBarAttribute as CFString, &menu)
        guard error == .success, let menu, CFGetTypeID(menu) == AXUIElementGetTypeID() else {
            return nil
        }
        let menuElement = menu as! AXUIElement
        let frames = axChildren(menuElement).compactMap { accessibilityFrame($0, top: top) }
        guard let first = frames.min(by: { $0.minX < $1.minX }), let end = frames.map(\.maxX).max() else {
            return nil
        }
        let menuWidth = end - (accessibilityFrame(menuElement, top: top)?.minX ?? first.minX)
        var statusItems: [(NSRect, Bool)] = []
        for process in statusPIDs {
            let root = AXUIElementCreateApplication(process.pid)
            AXUIElementSetMessagingTimeout(root, 0.15)
            if let extras = axValue(root, kAXExtrasMenuBarAttribute), CFGetTypeID(extras) == AXUIElementGetTypeID() {
                for child in axChildren(extras as! AXUIElement) {
                    guard let frame = accessibilityFrame(child, top: top) else { continue }
                    statusItems.append((frame, isWorkspaceStatus(child)))
                }
            }
            // macOS 27 hosts third-party status buttons in window children rather than Menu Extras.
            if process.bundle == "com.apple.MenuBarAgent" {
                for window in axChildren(root) where axValue(window, kAXRoleAttribute) as? String == kAXWindowRole {
                    for child in axChildren(window) {
                        guard let frame = accessibilityFrame(child, top: top), frame.height <= 80 else { continue }
                        statusItems.append((frame, isWorkspaceStatus(child)))
                    }
                }
            }
        }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let bars = windows.compactMap { window -> NSRect? in
            guard window[kCGWindowLayer as String] as? Int == 24,
                  let bounds = window[kCGWindowBounds as String] as? [String: NSNumber],
                  let x = bounds["X"]?.doubleValue, let y = bounds["Y"]?.doubleValue,
                  let width = bounds["Width"]?.doubleValue, let height = bounds["Height"]?.doubleValue,
                  height > 0, height <= 80 else { return nil }
            return NSRect(x: x, y: top - y - height, width: width, height: height)
        }
        return MenuGeometry(menuWidth: menuWidth, bars: bars, statusItems: statusItems)
    }
}
