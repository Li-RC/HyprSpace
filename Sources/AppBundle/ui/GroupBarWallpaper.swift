import AppKit
import ImageIO

enum GroupBarContrast: Equatable {
    case light, dark

    static func choose(brightness: CGFloat, current: GroupBarContrast?) -> GroupBarContrast {
        // A small dead band avoids flashing between appearances on textured wallpaper.
        let threshold: CGFloat = current == .dark ? 0.45 : current == .light ? 0.55 : 0.5
        return brightness >= threshold ? .dark : .light
    }
}

func wallpaperImageFrame(size: CGSize, screen: NSRect, scaling: NSImageScaling, clipping: Bool) -> NSRect {
    if scaling == .scaleAxesIndependently { return screen }
    let fit = min(screen.width / size.width, screen.height / size.height)
    let fill = max(screen.width / size.width, screen.height / size.height)
    let scale: CGFloat = switch scaling {
        case .scaleNone: 1
        case .scaleProportionallyDown: min(1, fit)
        default: clipping ? fill : fit
    }
    let width = size.width * scale, height = size.height * scale
    return NSRect(x: screen.midX - width / 2, y: screen.midY - height / 2, width: width, height: height)
}

// Read a small wallpaper thumbnail, never capture the screen or decode on every drag event.
@MainActor
final class GroupBarWallpaper {
    static let shared = GroupBarWallpaper()

    private struct Entry {
        var checked: Double
        let url: URL?
        let modified: Date?
        var bitmap: NSBitmapImageRep?
        var size: CGSize
        let scaling: NSImageScaling
        let clipping: Bool
        let fill: NSColor?
    }
    private var cache: [NSScreen: Entry] = [:]

    func brightness(in bar: NSRect, on screen: NSScreen) -> CGFloat? {
        let now = ProcessInfo.processInfo.systemUptime
        if cache[screen] == nil || now - cache[screen]!.checked >= 2 {
            let url = NSWorkspace.shared.desktopImageURL(for: screen)
            let modified = url.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            let options = NSWorkspace.shared.desktopImageOptions(for: screen)
            let scaling = (options?[.imageScaling] as? NSNumber).flatMap { NSImageScaling(rawValue: $0.uintValue) }
                ?? .scaleProportionallyUpOrDown
            let clipping = options?[.allowClipping] as? Bool ?? true
            let fill = options?[.fillColor] as? NSColor
            var bitmap = cache[screen]?.bitmap
            var size = cache[screen]?.size ?? .zero
            if cache[screen] == nil || cache[screen]?.url != url || cache[screen]?.modified != modified {
                bitmap = nil
                size = .zero
            }
            cache[screen] = Entry(checked: now, url: url, modified: modified, bitmap: bitmap, size: size,
                                  scaling: scaling, clipping: clipping, fill: fill)
            if let url, bitmap == nil {
                Task {
                    let decoded = await Task.detached(priority: .utility) { Self.thumbnail(at: url) }.value
                    guard cache[screen]?.url == url, cache[screen]?.modified == modified,
                          let (image, size) = decoded else { return }
                    cache[screen]?.bitmap = NSBitmapImageRep(cgImage: image)
                    cache[screen]?.size = size
                    WindowDecorations.shared.refresh()
                }
            }
        }
        guard let entry = cache[screen] else { return nil }
        guard let bitmap = entry.bitmap, entry.size.width > 0, entry.size.height > 0 else {
            return entry.fill.flatMap(wallpaperColorBrightness)
        }
        let image = wallpaperImageFrame(size: entry.size, screen: screen.frame, scaling: entry.scaling, clipping: entry.clipping)
        return wallpaperBrightness(bitmap, in: bar, imageFrame: image, fill: entry.fill)
    }

    nonisolated private static func thumbnail(at url: URL) -> (CGImage, CGSize)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 128,
              ] as CFDictionary) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        var size = CGSize(width: (properties?[kCGImagePropertyPixelWidth as String] as? NSNumber)?.doubleValue ?? Double(image.width),
                          height: (properties?[kCGImagePropertyPixelHeight as String] as? NSNumber)?.doubleValue ?? Double(image.height))
        if let orientation = (properties?[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue,
           (5 ... 8).contains(orientation) { size = CGSize(width: size.height, height: size.width) }
        return (image, size)
    }
}

func wallpaperBrightness(_ bitmap: NSBitmapImageRep, in bar: NSRect, imageFrame image: NSRect, fill: NSColor?) -> CGFloat? {
    var samples: [CGFloat] = []
    for x in 0 ..< 8 {
        for y in 0 ..< 3 {
            let point = CGPoint(x: bar.minX + bar.width * (CGFloat(x) + 0.5) / 8,
                                y: bar.minY + bar.height * (CGFloat(y) + 0.5) / 3)
            if image.contains(point) {
                let pixelX = min(bitmap.pixelsWide - 1, max(0, Int((point.x - image.minX) / image.width * CGFloat(bitmap.pixelsWide))))
                let pixelY = min(bitmap.pixelsHigh - 1, max(0, Int((image.maxY - point.y) / image.height * CGFloat(bitmap.pixelsHigh))))
                if let color = bitmap.colorAt(x: pixelX, y: pixelY), let brightness = wallpaperColorBrightness(color) { samples.append(brightness) }
            } else if let fill = fill, let brightness = wallpaperColorBrightness(fill) {
                samples.append(brightness)
            }
        }
    }
    return samples.isEmpty ? nil : samples.reduce(0, +) / CGFloat(samples.count)
}

private func wallpaperColorBrightness(_ color: NSColor) -> CGFloat? {
    guard let color = color.usingColorSpace(.sRGB) else { return nil }
    return 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
}
