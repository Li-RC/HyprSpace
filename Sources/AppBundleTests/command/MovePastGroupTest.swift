@testable import AppBundle
import Common
import XCTest

@MainActor
final class MovePastGroupTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testDirectionalMoveSwapsWithGroupWithoutJoining() async {
        for direction in CardinalDirection.allCases {
            setUpWorkspacesForTests()
            let workspace = Workspace.get(byName: name)
            let root = workspace.rootTilingContainer
            root.changeOrientation(direction.orientation)
            let member = TestWindow.new(id: 1, parent: root)
            let group = member.createWindowGroup()
            let active = TestWindow.new(id: 2, parent: group)
            let moving = TestWindow.new(id: 3, parent: root)
            if direction.isPositive {
                moving.bind(to: root, adaptiveWeight: 1, index: 0)
            }
            XCTAssertTrue(moving.focusWindow())
            let result = await parseCommand("move \(direction.rawValue)").cmdOrDie.run(.defaultEnv, .emptyStdin)
            XCTAssertEqual(result.exitCode.rawValue, 0)
            XCTAssertNil(moving.windowGroup)
            XCTAssertEqual(group.children, [member, active])
            XCTAssertEqual(group.mostRecentWindowRecursive, active)
            XCTAssertEqual(root.children, direction.isPositive ? [group, moving] : [moving, group])
            XCTAssertEqual(focus.windowOrNil, moving)
        }
    }

    func testMoveIntoNestedSplitStopsOutsideGroup() async {
        for direction in CardinalDirection.allCases {
            setUpWorkspacesForTests()
            let workspace = Workspace.get(byName: name)
            let root = workspace.rootTilingContainer
            root.changeOrientation(direction.orientation)
            let branch = TilingContainer(parent: root, adaptiveWeight: 1, direction.orientation.opposite, .tiles, index: 0)
            let other = TestWindow.new(id: 1, parent: branch)
            let member = TestWindow.new(id: 2, parent: branch)
            let group = member.createWindowGroup()
            let active = TestWindow.new(id: 3, parent: group)
            let moving = TestWindow.new(id: 4, parent: root)
            if direction.isPositive { moving.bind(to: root, adaptiveWeight: 1, index: 0) }
            XCTAssertTrue(moving.focusWindow())
            // Moving the source marks it recent at the root, without altering the
            // neighbor branch's selected group or the group's active member.
            let result = await parseCommand("move \(direction.rawValue)").cmdOrDie.run(.defaultEnv, .emptyStdin)
            XCTAssertEqual(result.exitCode.rawValue, 0)
            XCTAssertNil(moving.windowGroup)
            XCTAssertEqual(group.children, [member, active])
            XCTAssertEqual(group.mostRecentWindowRecursive, active)
            XCTAssertEqual(branch.children, direction.isPositive ? [other, group, moving] : [other, moving, group])
        }
    }
}

extension MovePastGroupTest {
    func testRepeatedMoveRightFromActiveFinderMovesWholeGroupAndStopsAtEdge() async throws {
        setUpWorkspacesForTests()
        config.enableDwindleTiling = true
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let code = TestWindow.new(id: 1, parent: root)
        let group = code.createWindowGroup()
        let finder = TestWindow.new(id: 2, parent: group)
        let codex = TestWindow.new(id: 3, parent: root)
        XCTAssertTrue(finder.focusWindow())
        workspace.normalizeContainers()
        try await workspace.layoutWorkspace()
        let move = parseCommand("move right").cmdOrDie
        for _ in 0 ..< 50 {
            let result = await move.run(.defaultEnv, .emptyStdin)
            XCTAssertEqual(result.exitCode.rawValue, 0)
            workspace.normalizeContainers()
            try await workspace.layoutWorkspace()
            XCTAssertEqual(group.children, [code, finder])
            XCTAssertEqual(group.mostRecentWindowRecursive, finder)
            XCTAssertEqual(workspace.rootTilingContainer.children, [codex, group])
            XCTAssertTrue(workspace.rootTilingContainer === root)
            XCTAssertEqual(focus.windowOrNil, finder)
            XCTAssertNil(code.lastAppliedLayoutPhysicalRect)
            XCTAssertNotNil(finder.lastAppliedLayoutPhysicalRect)
            XCTAssertLessThanOrEqual(codex.lastAppliedLayoutPhysicalRect!.maxX, finder.lastAppliedLayoutPhysicalRect!.minX)
        }
    }

    func testGroupedSourceMovesAsOneTileInEveryDirection() async {
        for direction in CardinalDirection.allCases {
            setUpWorkspacesForTests()
            config.enableDwindleTiling = true
            let workspace = Workspace.get(byName: name)
            let root = workspace.rootTilingContainer
            root.changeOrientation(direction.orientation)
            let member = TestWindow.new(id: 1, parent: root)
            let group = member.createWindowGroup()
            let active = TestWindow.new(id: 2, parent: group)
            let other = TestWindow.new(id: 3, parent: root)
            if !direction.isPositive { group.bind(to: root, adaptiveWeight: 1, index: 1) }
            XCTAssertTrue(active.focusWindow())
            for _ in 0 ..< 10 {
                let result = await parseCommand("move \(direction.rawValue)").cmdOrDie.run(.defaultEnv, .emptyStdin)
                XCTAssertEqual(result.exitCode.rawValue, 0)
                workspace.normalizeContainers()
                XCTAssertEqual(root.children, direction.isPositive ? [other, group] : [group, other])
                XCTAssertEqual(group.children, [member, active])
                XCTAssertEqual(group.mostRecentWindowRecursive, active)
            }
        }
    }

    func testRootGroupCannotBeMovedInsideItself() async {
        config.enableDwindleTiling = true
        let workspace = Workspace.get(byName: name)
        let member = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = member.createWindowGroup()
        let active = TestWindow.new(id: 2, parent: group)
        XCTAssertTrue(active.focusWindow())
        workspace.normalizeContainers()
        XCTAssertTrue(workspace.rootTilingContainer === group)
        for direction in CardinalDirection.allCases {
            let result = await parseCommand("move --boundaries-action create-implicit-container \(direction.rawValue)")
                .cmdOrDie.run(.defaultEnv, .emptyStdin)
            XCTAssertEqual(result.exitCode.rawValue, 0)
            XCTAssertTrue(workspace.rootTilingContainer === group)
            XCTAssertEqual(group.children, [member, active])
        }
    }

    func testDwindleExplicitBoundaryActionOverridesDefault() async {
        config.enableDwindleTiling = true
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let first = TestWindow.new(id: 1, parent: root)
        let edge = TestWindow.new(id: 2, parent: root)
        XCTAssertTrue(edge.focusWindow())
        let failure = await parseCommand("move --boundaries-action fail right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(failure.exitCode.rawValue, 2)
        XCTAssertTrue(workspace.rootTilingContainer === root)
        let move = await parseCommand("move --boundaries-action create-implicit-container down")
            .cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(move.exitCode.rawValue, 0)
        XCTAssertFalse(workspace.rootTilingContainer === root)
        XCTAssertEqual(workspace.rootTilingContainer.orientation, .v)
        XCTAssertEqual(workspace.rootTilingContainer.allLeafWindowsRecursive, [first, edge])
    }

    func testDwindleDefaultEdgeMoveDoesNotRestructureWorkspace() async throws {
        config.enableDwindleTiling = true
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let first = TestWindow.new(id: 1, parent: root)
        let edge = TestWindow.new(id: 2, parent: root)
        XCTAssertTrue(edge.focusWindow())
        try await workspace.layoutWorkspace()
        let before = edge.lastAppliedLayoutPhysicalRect!
        for _ in 0 ..< 20 {
            let result = await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
            XCTAssertEqual(result.exitCode.rawValue, 0)
            workspace.normalizeContainers()
            try await workspace.layoutWorkspace()
            XCTAssertTrue(workspace.rootTilingContainer === root)
            XCTAssertEqual(root.children, [first, edge])
            XCTAssertEqual(edge.lastAppliedLayoutPhysicalRect!.topLeftCorner, before.topLeftCorner)
            XCTAssertEqual(edge.lastAppliedLayoutPhysicalRect!.width, before.width)
        }
    }
}
