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

extension WindowDecorationTest {
    func testTabHitTestingUsesOnlyBarAndHandlesEdges() {
        let bounds = NSRect(x: 0, y: 0, width: 300, height: 200)
        XCTAssertEqual(groupTabIndex(at: CGPoint(x: 0, y: 190), in: bounds, memberCount: 3), 0)
        XCTAssertEqual(groupTabIndex(at: CGPoint(x: 99, y: 190), in: bounds, memberCount: 3), 0)
        XCTAssertEqual(groupTabIndex(at: CGPoint(x: 100, y: 190), in: bounds, memberCount: 3), 1)
        XCTAssertEqual(groupTabIndex(at: CGPoint(x: 299, y: 190), in: bounds, memberCount: 3), 2)
        XCTAssertNil(groupTabIndex(at: CGPoint(x: -1, y: 190), in: bounds, memberCount: 3))
        XCTAssertNil(groupTabIndex(at: CGPoint(x: 301, y: 190), in: bounds, memberCount: 3))
        XCTAssertNil(groupTabIndex(at: CGPoint(x: 150, y: 100), in: bounds, memberCount: 3))
        XCTAssertNil(groupTabIndex(at: CGPoint(x: 150, y: 190), in: bounds, memberCount: 0))
        XCTAssertNil(groupTabIndex(at: .zero, in: .zero, memberCount: 3))
    }

    @MainActor func testSelectingTabSwitchesActiveMemberAndFocus() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let second = TestWindow.new(id: 2, parent: group)
        XCTAssertTrue(first.isInactiveGroupMember)
        XCTAssertTrue(selectGroupTab(windowId: first.windowId, in: group))
        XCTAssertEqual(focus.windowOrNil, first)
        XCTAssertEqual(group.mostRecentWindowRecursive, first)
        XCTAssertTrue(second.isInactiveGroupMember)
        XCTAssertTrue(selectGroupTab(windowId: second.windowId, in: group))
        XCTAssertEqual(focus.windowOrNil, second)
    }

    @MainActor func testStaleTabDoesNotFocusWindowOutsideGroup() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let second = TestWindow.new(id: 2, parent: group)
        XCTAssertTrue(second.focusWindow())
        first.removeFromWindowGroup()
        XCTAssertFalse(selectGroupTab(windowId: first.windowId, in: group))
        XCTAssertFalse(selectGroupTab(windowId: 999, in: group))
        XCTAssertEqual(focus.windowOrNil, second)
        group.isWindowGroup = false
        XCTAssertFalse(selectGroupTab(windowId: second.windowId, in: group))
    }
}


extension WindowDecorationTest {
    @MainActor func testDecorationPanelsHideInExposeAndDoNotJoinFullscreenSpaces() {
        let panel = DecorationPanel()
        XCTAssertTrue(panel.collectionBehavior.contains(.transient))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenNone))
        XCTAssertFalse(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        panel.close()
    }

    func testDecorationOwnersExcludeHiddenAndOtherSpaceWindows() {
        let owners = onScreenDecorationOwners([
            [kCGWindowNumber as String: NSNumber(value: 1), kCGWindowIsOnscreen as String: true],
            [kCGWindowNumber as String: NSNumber(value: 2), kCGWindowIsOnscreen as String: false],
            [kCGWindowNumber as String: NSNumber(value: 3)],
        ])
        XCTAssertEqual(owners, [1])
        XCTAssertTrue(onScreenDecorationOwners([]).isEmpty)
    }
}


extension WindowDecorationTest {
    @MainActor func testBorderAndBarFollowNativeDragAndResizeFrames() {
        let border = DecorationPanel()
        let bar = DecorationPanel()
        defer { border.close(); bar.close() }
        let frames = [
            Rect(topLeftX: 100, topLeftY: 80, width: 800, height: 600),
            Rect(topLeftX: 260, topLeftY: 150, width: 800, height: 600),
            Rect(topLeftX: 260, topLeftY: 150, width: 1000, height: 700),
            Rect(topLeftX: -900, topLeftY: -250, width: 500, height: 400),
        ]
        for rect in frames {
            border.followOwner(rect, primaryScreenHeight: 1080, borderWidth: 2, isGroupBar: false)
            bar.followOwner(rect, primaryScreenHeight: 1080, borderWidth: 0, isGroupBar: true)
            XCTAssertEqual(border.frame, decorationFrame(rect, primaryScreenHeight: 1080, borderWidth: 2, barHeight: 0))
            XCTAssertEqual(bar.frame.minX, rect.minX)
            XCTAssertEqual(bar.frame.minY, 1080 - rect.minY + windowGroupBarGap)
            XCTAssertEqual(bar.frame.minY - (1080 - rect.minY), 8)
            XCTAssertEqual(bar.frame.width, rect.width)
            XCTAssertEqual(bar.frame.height, windowGroupBarHeight)
        }
    }
}
