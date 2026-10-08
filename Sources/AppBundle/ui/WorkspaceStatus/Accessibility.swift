// Adapted from Workspace Status. See legal/workspace-status/LICENSE.
import Foundation
import ApplicationServices

func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard unsafe AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
    return result
}

func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    axValue(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}
