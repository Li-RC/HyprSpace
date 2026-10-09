@testable import AppBundle
import Common
import XCTest

@MainActor
final class DwindleDropTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        config.enableDwindleTiling = true
        currentlyManipulatedWithMouseWindowId = nil
        TrayMenuModel.shared.isEnabled = true
        beginWindowMouseGesture(at: CGPoint(x: -10000, y: -10000))
    }

    func testDraggingAnyWindowEdgeNeverRetilesOnRelease() async throws {
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let target = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        try await workspace.layoutWorkspace()
        let rect = window.lastAppliedLayoutPhysicalRect!
        let edges = [CGPoint(x: rect.minX, y: rect.center.y), CGPoint(x: rect.maxX, y: rect.center.y),
                     CGPoint(x: rect.center.x, y: rect.minY), CGPoint(x: rect.center.x, y: rect.maxY),
                     rect.topLeftCorner, rect.bottomRightCorner]
        for edge in edges {
            beginWindowMouseGesture(at: edge)
            // A move can be delivered before the corresponding resize notification.
            let moved = Rect(topLeftX: rect.minX + 10, topLeftY: rect.minY + 10, width: rect.width, height: rect.height)
            recordDwindleMouseMove(window, from: rect, to: moved, mouseButtonDown: true)
            XCTAssertNil(currentlyManipulatedWithMouseWindowId)
            XCTAssertNotNil(window.lastAppliedLayoutPhysicalRect)
            XCTAssertFalse(finishMovingWindowWithMouse(at: target.lastAppliedLayoutPhysicalRect!.center))
            XCTAssertEqual(workspace.rootTilingContainer.children, [window, target])
        }
    }

    func testMoveAfterResizeStillCannotBecomeDrop() async throws {
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let target = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        try await workspace.layoutWorkspace()
        let rect = window.lastAppliedLayoutPhysicalRect!
        beginWindowMouseGesture(at: CGPoint(x: rect.center.x, y: rect.minY + 20))
        let resized = Rect(topLeftX: rect.minX + 10, topLeftY: rect.minY, width: rect.width - 10, height: rect.height)
        recordDwindleMouseMove(window, from: rect, to: resized, mouseButtonDown: true)
        let moved = Rect(topLeftX: resized.minX + 10, topLeftY: resized.minY, width: resized.width, height: resized.height)
        recordDwindleMouseMove(window, from: resized, to: moved, mouseButtonDown: true)
        XCTAssertFalse(finishMovingWindowWithMouse(at: point(.left, in: target.lastAppliedLayoutPhysicalRect!)))
        XCTAssertEqual(workspace.rootTilingContainer.children, [window, target])
    }

    private func point(_ direction: CardinalDirection, in rect: Rect) -> CGPoint {
        switch direction {
            case .left: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.center.y)
            case .right: CGPoint(x: rect.maxX - rect.width * 0.05, y: rect.center.y)
            case .up: CGPoint(x: rect.center.x, y: rect.minY + rect.height * 0.1)
            case .down: CGPoint(x: rect.center.x, y: rect.maxY - rect.height * 0.05)
        }
    }

    func testNativeDragThenReleaseCreatesSideBySideAfterInterveningLayout() async throws {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.changeOrientation(.v)
        let dragged = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let target = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        XCTAssertTrue(dragged.focusWindow())
        try await workspace.layoutWorkspace()
        let previous = dragged.lastAppliedLayoutPhysicalRect!
        let current = Rect(topLeftX: previous.minX + 100, topLeftY: previous.minY + 200,
                           width: previous.width, height: previous.height)
        recordDwindleMouseMove(dragged, from: previous, to: current, mouseButtonDown: true)
        XCTAssertEqual(currentlyManipulatedWithMouseWindowId, dragged.windowId)
        XCTAssertNil(dragged.lastAppliedLayoutPhysicalRect)
        // Layout work triggered by AX notifications must not move the drag source back.
        let appliedFrames = dragged.appliedFrames
        workspace.normalizeContainers()
        try await workspace.layoutWorkspace()
        XCTAssertEqual(dragged.appliedFrames, appliedFrames)
        // A delayed move event after mouse-up must not erase the recorded drag.
        recordDwindleMouseMove(dragged, from: current, to: previous, mouseButtonDown: false)
        XCTAssertTrue(finishMovingWindowWithMouse(at: point(.left, in: target.lastAppliedLayoutPhysicalRect!)))
        currentlyManipulatedWithMouseWindowId = nil
        workspace.normalizeContainers()
        try await workspace.layoutWorkspace()
        XCTAssertEqual(workspace.rootTilingContainer.orientation, .h)
        XCTAssertEqual(workspace.rootTilingContainer.children, [dragged, target])
        XCTAssertEqual(focus.windowOrNil, dragged)
        XCTAssertFalse(finishMovingWindowWithMouse(at: target.lastAppliedLayoutPhysicalRect!.center))
    }

    func testNativeResizeAndUnpressedMoveDoNotBecomeDrags() async throws {
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        try await workspace.layoutWorkspace()
        let previous = window.lastAppliedLayoutPhysicalRect!
        let resize = Rect(topLeftX: previous.minX + 20, topLeftY: previous.minY + 20,
                          width: previous.width - 20, height: previous.height - 20)
        recordDwindleMouseMove(window, from: previous, to: resize, mouseButtonDown: true)
        XCTAssertNil(currentlyManipulatedWithMouseWindowId)
        let move = Rect(topLeftX: previous.minX + 100, topLeftY: previous.minY,
                        width: previous.width, height: previous.height)
        recordDwindleMouseMove(window, from: previous, to: move, mouseButtonDown: false)
        XCTAssertNil(currentlyManipulatedWithMouseWindowId)
        XCTAssertEqual(window.lastAppliedLayoutPhysicalRect!.topLeftCorner, previous.topLeftCorner)
    }

    func testWideTileSideZonesWinNearTopAndIncludeBorderGap() {
        let rect = Rect(topLeftX: 8, topLeftY: 600, width: 1900, height: 450)
        XCTAssertEqual(dwindleDropDirection(at: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY + 20), in: rect), .left)
        XCTAssertEqual(dwindleDropDirection(at: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.minY + 20), in: rect), .right)
        XCTAssertEqual(dwindleDropDirection(at: CGPoint(x: rect.minX - 8, y: rect.center.y), in: rect), .left)
        XCTAssertEqual(dwindleDropDirection(at: CGPoint(x: rect.maxX + 8, y: rect.center.y), in: rect), .right)
        XCTAssertEqual(dwindleDropDirection(at: CGPoint(x: rect.center.x, y: rect.minY + 20), in: rect), .up)
        XCTAssertEqual(dwindleDropDirection(at: CGPoint(x: rect.center.x, y: rect.maxY - 20), in: rect), .down)
        XCTAssertNil(dwindleDropDirection(at: CGPoint(x: rect.maxX + 100, y: rect.center.y), in: rect))
    }

    func testBorderGapPreviewAndReleaseSelectSameHorizontalSplit() async throws {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.changeOrientation(.v)
        let dragged = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let target = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        try await workspace.layoutWorkspace()
        let rootRect = workspace.rootTilingContainer.lastAppliedLayoutPhysicalRect!
        let rect = target.lastAppliedLayoutPhysicalRect!
        let point = CGPoint(x: rect.maxX + 4, y: rect.minY + 20)
        let preview = dwindleDropTarget(dragged, at: point, in: workspace)!
        XCTAssertEqual(preview.window, target)
        XCTAssertEqual(preview.direction, .right)
        XCTAssertEqual(preview.previewRect.minX, rootRect.center.x)
        XCTAssertEqual(preview.previewRect.width, rootRect.width / 2)
        XCTAssertEqual(preview.previewRect.height, rootRect.height)
        XCTAssertTrue(dropDwindleWindow(dragged, at: point, in: workspace))
        workspace.normalizeContainers()
        XCTAssertEqual(workspace.rootTilingContainer.orientation, .h)
        XCTAssertEqual(workspace.rootTilingContainer.children, [target, dragged])
    }

    func testGroupPreviewShowsJoinOrSplitWithoutChangingMembership() async throws {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let active = TestWindow.new(id: 2, parent: group)
        let dragged = TestWindow.new(id: 3, parent: workspace.rootTilingContainer)
        try await workspace.layoutWorkspace()
        let rect = group.lastAppliedLayoutPhysicalRect!
        let center = dwindleDropTarget(dragged, at: rect.center, in: workspace)!
        XCTAssertNil(center.direction)
        XCTAssertEqual(center.previewRect.width, rect.width)
        XCTAssertEqual(center.previewRect.height, rect.height)
        let side = dwindleDropTarget(dragged, at: point(.left, in: rect), in: workspace)!
        XCTAssertEqual(side.direction, .left)
        XCTAssertEqual(group.children, [first, active])
        XCTAssertEqual(dragged.parent as? TilingContainer, workspace.rootTilingContainer)
    }

    func testPreviewHalvesUseRequestedDirectionOnSecondaryMonitor() {
        let rect = Rect(topLeftX: -1000, topLeftY: -300, width: 800, height: 600)
        for direction in CardinalDirection.allCases {
            let half = dwindleSplitPreviewRect(rect, direction: direction)
            XCTAssertEqual(half.width, direction.orientation == .h ? 400 : 800)
            XCTAssertEqual(half.height, direction.orientation == .v ? 300 : 600)
            XCTAssertEqual(half.minX, direction == .right ? rect.center.x : rect.minX)
            XCTAssertEqual(half.minY, direction == .down ? rect.center.y : rect.minY)
        }
    }

    func testStackedWindowsCanBeDroppedBackIntoSideBySideSplit() async throws {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.changeOrientation(.v)
        let dragged = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let target = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        try await workspace.layoutWorkspace()
        XCTAssertTrue(dropDwindleWindow(dragged, at: point(.left, in: target.lastAppliedLayoutPhysicalRect!), in: workspace))
        workspace.normalizeContainers()
        try await workspace.layoutWorkspace()
        XCTAssertEqual(workspace.rootTilingContainer.orientation, .h)
        XCTAssertEqual(workspace.rootTilingContainer.children, [dragged, target])
        XCTAssertLessThanOrEqual(dragged.lastAppliedLayoutPhysicalRect!.maxX, target.lastAppliedLayoutPhysicalRect!.minX)
        XCTAssertEqual(focus.windowOrNil, dragged)
    }

    func testRepeatedDropsChooseEverySplitDirectionWithoutGrowingTree() async throws {
        let workspace = Workspace.get(byName: name)
        let target = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let dragged = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        for _ in 0 ..< 10 {
            for direction in CardinalDirection.allCases {
                try await workspace.layoutWorkspace()
                let rect = target.lastAppliedLayoutPhysicalRect!
                XCTAssertTrue(dropDwindleWindow(dragged, at: point(direction, in: rect), in: workspace))
                workspace.normalizeContainers()
                let root = workspace.rootTilingContainer
                XCTAssertEqual(root.orientation, direction.orientation)
                XCTAssertEqual(root.children, direction.isPositive ? [target, dragged] : [dragged, target])
            }
        }
    }

    func testGroupEdgesSplitOutsideGroupWhileCenterAndBarJoin() async throws {
        for direction in CardinalDirection.allCases {
            setUpWorkspacesForTests()
            config.enableDwindleTiling = true
            let workspace = Workspace.get(byName: name)
            let member = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
            let group = member.createWindowGroup()
            let active = TestWindow.new(id: 2, parent: group)
            let dragged = TestWindow.new(id: 3, parent: workspace.rootTilingContainer)
            try await workspace.layoutWorkspace()
            XCTAssertTrue(dropDwindleWindow(dragged, at: point(direction, in: group.lastAppliedLayoutPhysicalRect!), in: workspace))
            workspace.normalizeContainers()
            XCTAssertEqual(group.children, [member, active])
            XCTAssertEqual(workspace.rootTilingContainer.orientation, direction.orientation)
            XCTAssertEqual(workspace.rootTilingContainer.children, direction.isPositive ? [group, dragged] : [dragged, group])
            try await workspace.layoutWorkspace()
            XCTAssertTrue(dropDwindleWindow(dragged, at: group.lastAppliedLayoutPhysicalRect!.center, in: workspace))
            XCTAssertEqual(group.children, [member, active, dragged])
        }
    }

    func testDraggingMemberToOwnGroupEdgeExtractsItWithoutLosingOthers() async throws {
        let workspace = Workspace.get(byName: name)
        let member = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = member.createWindowGroup()
        let dragged = TestWindow.new(id: 2, parent: group)
        workspace.normalizeContainers()
        try await workspace.layoutWorkspace()
        XCTAssertTrue(dropDwindleWindow(dragged, at: point(.right, in: group.lastAppliedLayoutPhysicalRect!), in: workspace))
        workspace.normalizeContainers()
        XCTAssertEqual(workspace.rootTilingContainer.children, [group, dragged])
        XCTAssertEqual(group.children, [member])
        XCTAssertNil(dragged.windowGroup)
    }

    func testFloatingWindowCanTileBesideNestedTarget() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let other = TestWindow.new(id: 1, parent: root)
        let branch = TilingContainer(parent: root, adaptiveWeight: 1, .v, .tiles, index: 1)
        let sibling = TestWindow.new(id: 2, parent: branch)
        let target = TestWindow.new(id: 3, parent: branch)
        let dragged = TestWindow.new(id: 4, parent: workspace.floatingWindowsContainer)
        try await workspace.layoutWorkspace()
        XCTAssertTrue(dropDwindleWindow(dragged, at: point(.left, in: target.lastAppliedLayoutPhysicalRect!), in: workspace))
        workspace.normalizeContainers()
        XCTAssertEqual(root.children, [other, branch])
        XCTAssertEqual(branch.children.first, sibling)
        let split = target.parent as! TilingContainer
        XCTAssertEqual(split.orientation, .h)
        XCTAssertEqual(split.children, [dragged, target])
        XCTAssertFalse(dragged.isFloating)
    }

    func testDropOnEmptyWorkspaceTransfersOnlyDraggedMember() async throws {
        let source = Workspace.get(byName: name)
        let destination = Workspace.get(byName: name + "-destination")
        let first = TestWindow.new(id: 1, parent: source.rootTilingContainer)
        let group = first.createWindowGroup()
        let dragged = TestWindow.new(id: 2, parent: group)
        XCTAssertTrue(dropDwindleWindow(dragged, at: CGPoint(x: 200, y: 200), in: destination))
        source.normalizeContainers()
        destination.normalizeContainers()
        XCTAssertEqual(group.children, [first])
        XCTAssertEqual(destination.rootTilingContainer.children, [dragged])
        XCTAssertEqual(dragged.nodeWorkspace, destination)
    }

    func testDropOnGroupBarJoinsAndFullscreenTargetRejectsDrop() async throws {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let active = TestWindow.new(id: 2, parent: group)
        let dragged = TestWindow.new(id: 3, parent: workspace.rootTilingContainer)
        try await workspace.layoutWorkspace()
        let rect = group.lastAppliedLayoutPhysicalRect!
        active.isFullscreen = true
        XCTAssertFalse(dropDwindleWindow(dragged, at: point(.right, in: rect), in: workspace))
        active.isFullscreen = false
        XCTAssertTrue(dropDwindleWindow(dragged, at: CGPoint(x: rect.center.x, y: rect.minY + 12), in: workspace))
        XCTAssertEqual(group.children, [first, active, dragged])
    }

    func testDropOnSelfOrOutsideWorkspaceDoesNotRestructureTree() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let dragged = TestWindow.new(id: 1, parent: root)
        try await workspace.layoutWorkspace()
        XCTAssertFalse(dropDwindleWindow(dragged, at: dragged.lastAppliedLayoutPhysicalRect!.center, in: workspace))
        XCTAssertFalse(dropDwindleWindow(dragged, at: CGPoint(x: -10000, y: -10000), in: workspace))
        XCTAssertTrue(workspace.rootTilingContainer === root)
        XCTAssertEqual(root.children, [dragged])
    }
}
