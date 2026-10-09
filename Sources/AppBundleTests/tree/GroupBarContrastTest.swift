@testable import AppBundle
import AppKit
import XCTest

final class GroupBarContrastTest: XCTestCase {
    func testGlassContrastsWithWallpaperAndDoesNotFlickerAtThreshold() {
        XCTAssertEqual(GroupBarContrast.choose(brightness: 0.9, current: nil), .dark)
        XCTAssertEqual(GroupBarContrast.choose(brightness: 0.1, current: nil), .light)
        XCTAssertEqual(GroupBarContrast.choose(brightness: 0.48, current: .dark), .dark)
        XCTAssertEqual(GroupBarContrast.choose(brightness: 0.52, current: .light), .light)
        XCTAssertEqual(GroupBarContrast.choose(brightness: 0.2, current: .dark), .light)
        XCTAssertEqual(GroupBarContrast.choose(brightness: 0.8, current: .light), .dark)
    }

    func testWallpaperAspectFillFitAndSecondaryScreenCoordinates() {
        let screen = NSRect(x: -1000, y: 300, width: 1000, height: 1000)
        let size = CGSize(width: 2000, height: 1000)
        XCTAssertEqual(wallpaperImageFrame(size: size, screen: screen, scaling: .scaleProportionallyUpOrDown, clipping: true),
                       NSRect(x: -1500, y: 300, width: 2000, height: 1000))
        XCTAssertEqual(wallpaperImageFrame(size: size, screen: screen, scaling: .scaleProportionallyUpOrDown, clipping: false),
                       NSRect(x: -1000, y: 550, width: 1000, height: 500))
        XCTAssertEqual(wallpaperImageFrame(size: size, screen: screen, scaling: .scaleAxesIndependently, clipping: true), screen)
    }

    @MainActor func testBarSamplesLocalWallpaperWithCorrectVerticalDirection() throws {
        let image = unsafe try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0 ..< 8 {
            for y in 0 ..< 8 {
                let value: CGFloat = y < 4 ? 1 : 0
                image.setColor(NSColor(deviceRed: value, green: value, blue: value, alpha: 1), atX: x, y: y)
            }
        }
        let frame = NSRect(x: 0, y: 0, width: 800, height: 800)
        let upper = try XCTUnwrap(wallpaperBrightness(image, in: NSRect(x: 0, y: 700, width: 800, height: 32), imageFrame: frame, fill: nil))
        let lower = try XCTUnwrap(wallpaperBrightness(image, in: NSRect(x: 0, y: 50, width: 800, height: 32), imageFrame: frame, fill: nil))
        XCTAssertGreaterThan(upper, 0.9)
        XCTAssertLessThan(lower, 0.1)
        XCTAssertEqual(GroupBarContrast.choose(brightness: upper, current: nil), .dark)
        XCTAssertEqual(GroupBarContrast.choose(brightness: lower, current: nil), .light)
        let fill = wallpaperBrightness(image, in: NSRect(x: -200, y: 100, width: 100, height: 32), imageFrame: frame, fill: .white)
        XCTAssertEqual(try XCTUnwrap(fill), 1, accuracy: 0.001)
    }

    @MainActor func testBarAppliesOppositeAppearanceToNativeAndDraggedGlass() {
        let bar = GroupBarView()
        bar.applyContrast(.dark)
        XCTAssertEqual(bar.appearance?.name, .darkAqua)
        bar.applyContrast(.light)
        XCTAssertEqual(bar.appearance?.name, .aqua)
    }
}
