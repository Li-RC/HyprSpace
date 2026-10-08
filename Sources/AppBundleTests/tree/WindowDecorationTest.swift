@testable import AppBundle
import XCTest

final class WindowDecorationTest: XCTestCase {
    @MainActor func testBordersAreOptInAndParseCustomStyle() {
        XCTAssertFalse(parseConfig("").config.windowBorders.enabled)
        let result = parseConfig("""
        [window-borders]
        enabled = true
        width = 3
        active-color = '#abcdef'
        inactive-color = '#123456'
        """)
        XCTAssertTrue(result.errors.isEmpty, "\(result.errors)")
        XCTAssertTrue(result.config.windowBorders.enabled)
        XCTAssertEqual(result.config.windowBorders.width, 3)
        XCTAssertEqual(result.config.windowBorders.activeColor.rgb, 0xabcdef)
        XCTAssertEqual(result.config.windowBorders.inactiveColor.rgb, 0x123456)
    }

    @MainActor func testInvalidBorderOptionsReportErrors() {
        for option in ["width = 0", "width = 9", "width = '2'", "enabled = 'true'", "active-color = '#abc'", "active-color = '#zzzzzz'", "inactive-color = '123456'", "unknown = true"] {
            XCTAssertFalse(parseConfig("[window-borders]\n" + option).errors.isEmpty, option)
        }
    }

    func testCoordinateConversionIncludesBorderAndGroupBarOnSecondaryScreen() {
        let rect = Rect(topLeftX: -800, topLeftY: -300, width: 600, height: 400)
        let frame = decorationFrame(rect, primaryScreenHeight: 1080, borderWidth: 2, barHeight: 24)
        XCTAssertEqual(frame.minX, -802)
        XCTAssertEqual(frame.minY, 978)
        XCTAssertEqual(frame.width, 604)
        XCTAssertEqual(frame.height, 428)
    }
}