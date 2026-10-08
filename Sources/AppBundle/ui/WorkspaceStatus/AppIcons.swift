// Adapted from Workspace Status. See legal/workspace-status/LICENSE.
import AppKit
import SwiftUI
import CoreText

@MainActor private var iconCache: [String: NSImage] = [:]
@MainActor func appIcon(_ bundle: String) -> NSImage {
    if let icon = iconCache[bundle] { return icon }
    let image: NSImage
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
        image = NSWorkspace.shared.icon(forFile: url.path)
    } else { image = NSImage(systemSymbolName: "app", accessibilityDescription: nil)! }
    iconCache[bundle] = image
    return image
}

struct AppIcon: View {
    let bundle: String
    var body: some View { Image(nsImage: appIcon(bundle)).resizable().frame(width: 20, height: 20) }
}

@MainActor func workspaceBadge(_ label: String, selected: Bool = true) -> NSImage {
    let font = NSFont.systemFont(ofSize: 12, weight: .bold)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: label,
        attributes: [.font: font, .foregroundColor: NSColor.black]))
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    let width = max(22, ceil(bounds.width) + 10)
    let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { _ in
        NSColor.black.setFill()
        let badge = NSBezierPath(roundedRect: NSRect(x: 0.75, y: 2.75, width: width - 1.5, height: 16.5), xRadius: 5, yRadius: 5)
        if selected { badge.fill() } else { NSColor.black.setStroke(); badge.lineWidth = 1.5; badge.stroke() }
        let context = NSGraphicsContext.current!.cgContext
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: width / 2 - bounds.midX, y: 11 - bounds.midY)
        // Cut the centered number out of the template's solid badge.
        if selected { context.setBlendMode(.destinationOut) }
        CTLineDraw(line, context)
        context.restoreGState()
        return true
    }
    image.isTemplate = true
    return image
}

@MainActor func menuBarSymbol(_ image: NSImage) -> NSImage {
    guard image.isTemplate else { return image }
    return NSImage(size: image.size, flipped: false) { bounds in
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSColor.white.setFill()
        bounds.fill(using: .sourceIn)
        return true
    }
}

@MainActor func iconStrip(_ bundles: [String]) -> NSImage {
    let width = CGFloat(bundles.count * 21 + 4)
    return NSImage(size: NSSize(width: width, height: 22), flipped: false) { _ in
        for (index, bundle) in bundles.enumerated() {
            appIcon(bundle).draw(in: NSRect(x: CGFloat(index * 21 + 4), y: 3, width: 16, height: 16))
        }
        return true
    }
}
