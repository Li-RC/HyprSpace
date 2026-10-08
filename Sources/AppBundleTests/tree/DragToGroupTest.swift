@testable import AppBundle
import Common
import XCTest

@MainActor
final class DragToGroupTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        config.enableDwindleTiling = true
        currentlyManipulatedWithMouseWindowId = nil
        TrayMenuModel.shared.isEnabled = true
    }

    private func makeGroup(in workspace: Workspace) -> (TilingContainer, TestWindow, TestWindow) {
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let active = TestWindow.new(id: 2, parent: group)
        return (group, first, active)
    }

    func testDroppingTiledWindowJoinsWithoutReplacingExistingMember() async throws {
        let workspace = Workspace.get(byName: name)
        let (group, first, active) = makeGroup(in: workspace)
        let dragged = TestWindow.new(id: 3, parent: workspace.rootTilingContainer)
        try await workspace.layoutWorkspace()
        let point = active.lastAppliedLayoutPhysicalRect!.center
        XCTAssertTrue(joinWindowToGroupUnderMouse(dragged, at: point, in: workspace))
        workspace.normalizeContainers()
        try await workspace.layoutWorkspace()
        XCTAssertEqual(group.children, [first, active, dragged])
        XCTAssertEqual(group.mostRecentWindowRecursive, dragged)
        XCTAssertTrue(first.isInactiveGroupMember)
        XCTAssertTrue(active.isInactiveGroupMember)
        XCTAssertNil(active.lastAppliedLayoutPhysicalRect)
        XCTAssertNotNil(dragged.lastAppliedLayoutPhysicalRect)
    }

    func testDroppingFloatingWindowOnBarJoinsGroup() async throws {
        let workspace = Workspace.get(byName: name)
        let (group, first, active) = makeGroup(in: workspace)
        let dragged = TestWindow.new(id: 3, parent: workspace.floatingWindowsContainer,
                                     rect: Rect(topLeftX: 100, topLeftY: 100, width: 300, height: 200))
        try await workspace.layoutWorkspace()
        let rect = group.lastAppliedLayoutPhysicalRect!
        let bar = CGPoint(x: rect.center.x, y: rect.minY + windowGroupBarHeight / 2)
        XCTAssertEqual(bar.findWindowRecursively(in: workspace.rootTilingContainer, virtual: false, fullscreenCoversAll: false), active)
        XCTAssertTrue(joinWindowToGroupUnderMouse(dragged, at: bar, in: workspace))
        XCTAssertFalse(dragged.isFloating)
        XCTAssertEqual(group.children, [first, active, dragged])
    }

    func testDroppingMemberOnItsOwnGroupDoesNotChangeOrder() async throws {
        let workspace = Workspace.get(byName: name)
        let (group, first, active) = makeGroup(in: workspace)
        try await workspace.layoutWorkspace()
        XCTAssertFalse(joinWindowToGroupUnderMouse(active, at: group.lastAppliedLayoutPhysicalRect!.center, in: workspace))
        XCTAssertEqual(group.children, [first, active])
    }

    func testDropOnOrdinaryTileDoesNotCreateGroup() async throws {
        let workspace = Workspace.get(byName: name)
        let target = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let dragged = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        try await workspace.layoutWorkspace()
        XCTAssertFalse(joinWindowToGroupUnderMouse(dragged, at: target.lastAppliedLayoutPhysicalRect!.center, in: workspace))
        XCTAssertNil(target.windowGroup)
        XCTAssertEqual(workspace.rootTilingContainer.children, [target, dragged])
    }

    func testDropAcrossWorkspacesLeavesSourceGroupIntact() async throws {
        let destination = Workspace.get(byName: name + "-destination")
        let (group, first, active) = makeGroup(in: destination)
        let source = Workspace.get(byName: name)
        let dragged = TestWindow.new(id: 3, parent: source.rootTilingContainer)
        let sourceGroup = dragged.createWindowGroup()
        let remaining = TestWindow.new(id: 4, parent: sourceGroup)
        try await destination.layoutWorkspace()
        XCTAssertTrue(joinWindowToGroupUnderMouse(dragged, at: group.lastAppliedLayoutPhysicalRect!.center, in: destination))
        source.normalizeContainers()
        destination.normalizeContainers()
        XCTAssertEqual(group.children, [first, active, dragged])
        XCTAssertEqual(sourceGroup.children, [remaining])
        XCTAssertTrue(sourceGroup.isWindowGroup)
        XCTAssertEqual(dragged.nodeWorkspace, destination)
    }

    func testDropOutsideGroupAndOnFullscreenDoesNothing() async throws {
        let workspace = Workspace.get(byName: name)
        let (group, first, active) = makeGroup(in: workspace)
        let dragged = TestWindow.new(id: 3, parent: workspace.rootTilingContainer)
        try await workspace.layoutWorkspace()
        XCTAssertFalse(joinWindowToGroupUnderMouse(dragged, at: CGPoint(x: -10000, y: -10000), in: workspace))
        active.isFullscreen = true
        XCTAssertFalse(joinWindowToGroupUnderMouse(dragged, at: group.lastAppliedLayoutPhysicalRect!.center, in: workspace))
        XCTAssertEqual(group.children, [first, active])
    }

    func testRepeatedCyclingKeepsActiveMemberInsideGroupTile() async throws {
        let workspace = Workspace.get(byName: name)
        let (group, first, active) = makeGroup(in: workspace)
        TestWindow.new(id: 3, parent: workspace.rootTilingContainer)
        for index in 0 ..< 20 {
            let selected = index.isMultiple(of: 2) ? first : active
            XCTAssertTrue(selected.focusWindow())
            try await workspace.layoutWorkspace()
            let tile = group.lastAppliedLayoutPhysicalRect!
            let rect = selected.lastAppliedLayoutPhysicalRect!
            XCTAssertEqual(rect.minX, tile.minX)
            XCTAssertEqual(rect.minY, tile.minY + windowGroupBarHeight + windowGroupBarGap)
            XCTAssertEqual(rect.width, tile.width)
            XCTAssertEqual(rect.height, tile.height - windowGroupBarHeight - windowGroupBarGap)
            let hidden = selected == first ? active : first
            XCTAssertNil(hidden.lastAppliedLayoutPhysicalRect)
            XCTAssertNil(hidden.lastAppliedLayoutVirtualRect)
        }
    }

    func testFullscreenBindingLeavesFloatingToggleAndInputMethodUntouched() throws {
        let result = parseConfig(try String(contentsOf: projectRoot.appending(path: "docs/config-examples/hyprspace-dwindle.toml"), encoding: .utf8))
        XCTAssertTrue(result.errors.isEmpty)
        let bindings = result.config.modes[mainModeId]!.bindings.values
        let descriptions = bindings.map(\.descriptionWithKeyCode)
        XCTAssertTrue(descriptions.contains("ctrl-f"))
        XCTAssertTrue(descriptions.contains("ctrl-shift-f"))
        XCTAssertFalse(descriptions.contains { $0.contains("space") })
    }
}
