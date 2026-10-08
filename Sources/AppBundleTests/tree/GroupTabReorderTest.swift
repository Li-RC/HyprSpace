@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class GroupTabReorderTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        config.enableDwindleTiling = true
    }

    func testReorderingInactiveMemberPreservesFocusHistoryWeightsAndMembership() {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let second = TestWindow.new(id: 2, parent: group, adaptiveWeight: 2)
        let third = TestWindow.new(id: 3, parent: group, adaptiveWeight: 3)
        let neighbor = TestWindow.new(id: 4, parent: workspace.rootTilingContainer)
        XCTAssertTrue(second.focusWindow())
        XCTAssertTrue(neighbor.focusWindow())
        let groupHistory = Array(group.mruChildren)
        let rootHistory = Array(workspace.rootTilingContainer.mruChildren)
        XCTAssertTrue(group.reorderWindowGroupMember(first.windowId, to: 2))
        XCTAssertEqual(group.children, [second, third, first])
        XCTAssertEqual(Array(group.mruChildren), groupHistory)
        XCTAssertEqual(Array(workspace.rootTilingContainer.mruChildren), rootHistory)
        XCTAssertEqual(group.mostRecentWindowRecursive, second)
        XCTAssertEqual(focus.windowOrNil, neighbor)
        XCTAssertTrue(first.isInactiveGroupMember)
        XCTAssertEqual(second.getWeight(.h), 2)
        XCTAssertEqual(third.getWeight(.h), 3)
        XCTAssertEqual(first.windowGroup, group)
    }

    func testReorderingActiveMemberAndCyclingUsesNewOrder() async {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let second = TestWindow.new(id: 2, parent: group)
        let third = TestWindow.new(id: 3, parent: group)
        XCTAssertTrue(third.focusWindow())
        XCTAssertTrue(group.reorderWindowGroupMember(third.windowId, to: 0))
        workspace.normalizeContainers()
        XCTAssertEqual(group.children, [third, first, second])
        XCTAssertEqual(focus.windowOrNil, third)
        let next = await parseCommand("group next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(next.exitCode.rawValue, 0)
        XCTAssertEqual(focus.windowOrNil, first)
        let previous = await parseCommand("group prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(previous.exitCode.rawValue, 0)
        XCTAssertEqual(focus.windowOrNil, third)
    }

    func testRepeatedReordersInBothDirectionsKeepEveryMemberOnce() {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let second = TestWindow.new(id: 2, parent: group)
        let third = TestWindow.new(id: 3, parent: group)
        XCTAssertTrue(second.focusWindow())
        for _ in 0 ..< 20 {
            XCTAssertTrue(group.reorderWindowGroupMember(first.windowId, to: 2))
            XCTAssertEqual(group.children, [second, third, first])
            XCTAssertTrue(group.reorderWindowGroupMember(first.windowId, to: 0))
            XCTAssertEqual(group.children, [first, second, third])
            XCTAssertEqual(group.mostRecentWindowRecursive, second)
            XCTAssertEqual(focus.windowOrNil, second)
        }
    }

    func testInvalidAndStaleReordersDoNotChangeGroup() {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let second = TestWindow.new(id: 2, parent: group)
        XCTAssertFalse(group.reorderWindowGroupMember(999, to: 0))
        XCTAssertFalse(group.reorderWindowGroupMember(first.windowId, to: -1))
        XCTAssertFalse(group.reorderWindowGroupMember(first.windowId, to: 2))
        XCTAssertEqual(group.children, [first, second])
        first.removeFromWindowGroup()
        XCTAssertFalse(group.reorderWindowGroupMember(first.windowId, to: 0))
        XCTAssertEqual(group.children, [second])
        XCTAssertTrue(group.reorderWindowGroupMember(second.windowId, to: 0))
        group.isWindowGroup = false
        XCTAssertFalse(group.reorderWindowGroupMember(second.windowId, to: 0))
    }

    func testDragThresholdAndOutsideReleaseKeepClicksDistinctFromReorders() {
        let bounds = NSRect(x: 0, y: 0, width: 300, height: windowGroupBarHeight)
        var drag = GroupTabDrag(windowId: 1, origin: CGPoint(x: 50, y: 16))
        drag.update(at: CGPoint(x: 52, y: 17), in: bounds, memberCount: 3)
        XCTAssertFalse(drag.isDragging)
        XCTAssertNil(drag.targetIndex)
        drag.update(at: CGPoint(x: 250, y: 16), in: bounds, memberCount: 3)
        XCTAssertTrue(drag.isDragging)
        XCTAssertEqual(drag.targetIndex, 2)
        drag.update(at: CGPoint(x: 250, y: -1), in: bounds, memberCount: 3)
        XCTAssertTrue(drag.isDragging)
        XCTAssertNil(drag.targetIndex)
        drag.update(at: CGPoint(x: 50, y: 16), in: bounds, memberCount: 3)
        XCTAssertTrue(drag.isDragging)
        XCTAssertEqual(drag.targetIndex, 0)
    }
}
