@testable import AppBundle
import Common
import XCTest

@MainActor
final class WindowGroupTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        config.enableDwindleTiling = true
        TrayMenuModel.shared.isEnabled = true
    }

    @discardableResult
    private func run(_ action: String, _ window: Window) async -> Int32 {
        await parseCommand("group --window-id \(window.windowId) \(action)").cmdOrDie
            .run(.defaultEnv, .emptyStdin).exitCode.rawValue
    }

    func testGroupSurvivesNormalizationAndNewWindowsJoinIt() async {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let result = await run("toggle", first)
        XCTAssertEqual(result, 0)
        workspace.normalizeContainers()
        XCTAssertNotNil(first.windowGroup)
        for id in 2 ... 4 {
            let binding = unbindAndGetBindingDataForNewTilingWindow(workspace, window: nil)
            TestWindow.new(id: UInt32(id), parent: binding.parent)
            workspace.normalizeContainers()
        }
        let group = first.windowGroup!
        XCTAssertEqual(group.children.count, 4)
        XCTAssertEqual(group.mostRecentWindowRecursive?.windowId, 4)
        XCTAssertTrue(first.isInactiveGroupMember)
        XCTAssertEqual(group.allLeafWindowsRecursive.filter { !$0.isInactiveGroupMember }.count, 1)
    }

    func testCyclingWrapsAndNativeFocusSelectsMember() async {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let second = TestWindow.new(id: 2, parent: group)
        XCTAssertTrue(second.focusWindow())
        let next = await run("next", second)
        XCTAssertEqual(next, 0)
        XCTAssertEqual(focus.windowOrNil, first)
        let prev = await run("prev", first)
        XCTAssertEqual(prev, 0)
        XCTAssertEqual(focus.windowOrNil, second)
        XCTAssertTrue(first.focusWindow())
        XCTAssertEqual(group.mostRecentWindowRecursive, first)
        XCTAssertTrue(second.isInactiveGroupMember)
    }

    func testClosingActiveMemberSelectsRemainingAndClosingLastClearsGroup() {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let second = TestWindow.new(id: 2, parent: group)
        second.unbindFromParent()
        workspace.normalizeContainers()
        XCTAssertTrue(group.isWindowGroup)
        XCTAssertEqual(group.mostRecentWindowRecursive, first)
        XCTAssertFalse(first.isInactiveGroupMember)
        first.unbindFromParent()
        workspace.normalizeContainers()
        XCTAssertFalse(workspace.rootTilingContainer.isWindowGroup)
        let next = TestWindow.new(id: 3, parent: workspace.rootTilingContainer)
        XCTAssertNil(next.windowGroup)
    }

    func testMergeGroupsKeepsMembersAndFocusedWindow() async {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let second = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        let left = first.createWindowGroup()
        let third = TestWindow.new(id: 3, parent: left)
        let right = second.createWindowGroup()
        let fourth = TestWindow.new(id: 4, parent: right)
        XCTAssertTrue(third.focusWindow())
        let joined = await run("join-right", third)
        XCTAssertEqual(joined, 0)
        workspace.normalizeContainers()
        XCTAssertEqual(Set(right.allLeafWindowsRecursive), Set([first, second, third, fourth]))
        XCTAssertEqual(right.mostRecentWindowRecursive, third)
        XCTAssertEqual(focus.windowOrNil, third)
        XCTAssertEqual(workspace.rootTilingContainer, right)
    }

    func testRemoveFromRootGroupCreatesSeparateTile() async {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let second = TestWindow.new(id: 2, parent: group)
        workspace.normalizeContainers()
        XCTAssertTrue(group.isRootContainer)
        let removed = await run("remove", second)
        XCTAssertEqual(removed, 0)
        workspace.normalizeContainers()
        XCTAssertEqual(workspace.rootTilingContainer.children, [group, second])
        XCTAssertEqual(first.windowGroup, group)
        XCTAssertNil(second.windowGroup)
    }

    func testToggleExtractsOnlyTargetAndPreservesRemainingGroupAndFocus() async {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let second = TestWindow.new(id: 2, parent: group)
        let third = TestWindow.new(id: 3, parent: group)
        XCTAssertTrue(second.focusWindow())
        let toggled = await run("toggle", second)
        XCTAssertEqual(toggled, 0)
        workspace.normalizeContainers()
        XCTAssertEqual(group.children, [first, third])
        XCTAssertTrue(group.isWindowGroup)
        XCTAssertEqual(first.windowGroup, group)
        XCTAssertEqual(third.windowGroup, group)
        XCTAssertNil(second.windowGroup)
        XCTAssertEqual(workspace.rootTilingContainer.children, [group, second])
        XCTAssertEqual(workspace.rootTilingContainer.mostRecentWindowRecursive, second)
        XCTAssertEqual(focus.windowOrNil, second)
    }

    func testToggleExtractsLastMemberOfRootGroup() async {
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        window.createWindowGroup()
        workspace.normalizeContainers()
        XCTAssertTrue(workspace.rootTilingContainer.isWindowGroup)
        XCTAssertTrue(window.focusWindow())
        let result = await run("toggle", window)
        XCTAssertEqual(result, 0)
        workspace.normalizeContainers()
        XCTAssertNil(window.windowGroup)
        XCTAssertFalse(workspace.rootTilingContainer.isWindowGroup)
        XCTAssertEqual(workspace.rootTilingContainer.children, [window])
        XCTAssertEqual(focus.windowOrNil, window)
    }

    func testDirectionalFocusSkipsHiddenMembersAndResizeChangesWholeTile() async {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let neighbor = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let active = TestWindow.new(id: 3, parent: group)
        XCTAssertTrue(active.focusWindow())
        let resized = await parseCommand("resize width +10").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(resized.exitCode.rawValue, 0)
        XCTAssertEqual(group.getWeight(.h), 11)
        XCTAssertEqual(first.getWeight(.h), 1)
        let focused = await FocusCommand.new(direction: .right).run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(focused.exitCode.rawValue, 0)
        XCTAssertEqual(focus.windowOrNil, neighbor)
        let back = await FocusCommand.new(direction: .left).run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(back.exitCode.rawValue, 0)
        XCTAssertEqual(focus.windowOrNil, active)
    }

    func testOnlyActiveMemberReceivesLayoutAndBarReservesSpace() async throws {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let second = TestWindow.new(id: 2, parent: group)
        workspace.normalizeContainers()
        try await workspace.layoutWorkspace()
        XCTAssertEqual(first.appliedFrames, 0)
        XCTAssertEqual(second.appliedFrames, 1)
        XCTAssertNil(first.lastAppliedLayoutPhysicalRect)
        XCTAssertEqual(second.lastAppliedLayoutPhysicalRect!.minY, group.lastAppliedLayoutPhysicalRect!.minY + windowGroupBarHeight + windowGroupBarGap)
        XCTAssertTrue(first.focusWindow())
        try await workspace.layoutWorkspace()
        XCTAssertEqual(first.appliedFrames, 1)
        XCTAssertNil(second.lastAppliedLayoutPhysicalRect)
    }

    func testMovingMemberToWorkspaceLeavesRemainingGroupIntact() {
        let source = Workspace.get(byName: name)
        let destination = Workspace.get(byName: name + "-destination")
        let first = TestWindow.new(id: 1, parent: source.rootTilingContainer)
        let group = first.createWindowGroup()
        let second = TestWindow.new(id: 2, parent: group)
        XCTAssertEqual(moveWindowToWorkspace(second, destination, CmdIoImpl.emptyStdinIgnoringOut,
                                            focusFollowsWindow: false, failIfNoop: false), .succ)
        source.normalizeContainers()
        destination.normalizeContainers()
        XCTAssertEqual(group.children, [first])
        XCTAssertTrue(group.isWindowGroup)
        XCTAssertNil(second.windowGroup)
        XCTAssertEqual(second.nodeWorkspace, destination)
    }

    func testDirectionalMoveMovesWholeGroup() async {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let active = TestWindow.new(id: 3, parent: group)
        XCTAssertTrue(active.focusWindow())
        let result = await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode.rawValue, 0)
        workspace.normalizeContainers()
        XCTAssertEqual(active.windowGroup, group)
        XCTAssertTrue(group.isWindowGroup)
        XCTAssertEqual(group.children, [first, active])
        XCTAssertEqual(workspace.rootTilingContainer.children.last, group)
    }

    func testFullscreenGroupMemberUsesWholeMonitorWithoutBar() async throws {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let active = TestWindow.new(id: 2, parent: group)
        active.isFullscreen = true
        XCTAssertTrue(active.focusWindow())
        try await workspace.layoutWorkspace()
        XCTAssertTrue(active.isFullscreen)
        XCTAssertNil(active.lastAppliedLayoutPhysicalRect)
        XCTAssertNil(first.lastAppliedLayoutPhysicalRect)
        active.isFullscreen = false
        try await workspace.layoutWorkspace()
        XCTAssertNotNil(active.lastAppliedLayoutPhysicalRect)
    }

    func testFloatingLayoutProvidesActualFrameForBorder() async throws {
        let workspace = Workspace.get(byName: name)
        let rect = Rect(topLeftX: 100, topLeftY: 100, width: 300, height: 200)
        let floating = TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer, rect: rect)
        try await workspace.layoutWorkspace()
        XCTAssertEqual(floating.lastAppliedLayoutPhysicalRect?.topLeftCorner, rect.topLeftCorner)
        XCTAssertEqual(floating.lastAppliedLayoutPhysicalRect?.width, rect.width)
        XCTAssertEqual(floating.lastAppliedLayoutPhysicalRect?.height, rect.height)
    }

    func testFrozenTreeRecordsGroupAndActiveMember() {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        TestWindow.new(id: 2, parent: group)
        first.markAsMostRecentChild()
        let frozen = FrozenContainer(group)
        XCTAssertTrue(frozen.isWindowGroup)
        XCTAssertEqual(frozen.activeWindowId, first.windowId)
        XCTAssertEqual(frozen.children.count, 2)
    }

    func testFloatingWindowCannotGroupAndMissingNeighborIsNoop() async {
        let workspace = Workspace.get(byName: name)
        let floating = TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer)
        let invalid = await run("toggle", floating)
        XCTAssertNotEqual(invalid, 0)
        let tiled = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        let missing = await run("join-left", tiled)
        XCTAssertNotEqual(missing, 0)
        XCTAssertNil(tiled.windowGroup)
    }
}
