@testable import AppBundle
import Common
import XCTest

@MainActor
final class DwindleTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        config.enableDwindleTiling = true
    }

    @discardableResult
    private func insert(_ id: UInt32, into workspace: Workspace) -> TestWindow {
        if workspace.lastAppliedLayoutPhysicalRect == nil {
            workspace.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 1200, height: 800)
        }
        let data = unbindAndGetBindingDataForNewTilingWindow(workspace, window: nil)
        let window = TestWindow.new(id: id, parent: data.parent, adaptiveWeight: data.adaptiveWeight)
        workspace.normalizeContainers()
        return window
    }

    func testSplitsFocusedTileAlongLongerDimension() {
        let workspace = Workspace.get(byName: name)
        let first = insert(1, into: workspace)
        first.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 1200, height: 800)
        let second = insert(2, into: workspace)
        let root = workspace.rootTilingContainer
        XCTAssertEqual(root.children, [first, second])
        XCTAssertEqual(root.orientation, .h)

        second.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 600, topLeftY: 0, width: 600, height: 800)
        let third = insert(3, into: workspace)
        let split = second.parent as! TilingContainer
        XCTAssertEqual(root.children.first, first)
        XCTAssertEqual(root.children.count, 2)
        XCTAssertEqual(split.children, [second, third])
        XCTAssertEqual(split.orientation, .v)

        first.markAsMostRecentChild()
        let fourth = insert(4, into: workspace)
        XCTAssertEqual((first.parent as! TilingContainer).children, [first, fourth])
        XCTAssertEqual((first.parent as! TilingContainer).orientation, .v)
        XCTAssertEqual(split.children, [second, third])
    }

    func testClosingWindowCollapsesSplitWithoutFlattenConfig() {
        let workspace = Workspace.get(byName: name)
        let first = insert(1, into: workspace)
        let second = insert(2, into: workspace)
        let third = insert(3, into: workspace)
        third.unbindFromParent()
        workspace.normalizeContainers()
        XCTAssertEqual(workspace.rootTilingContainer.children, [first, second])
        XCTAssertEqual(workspace.rootTilingContainer.mostRecentWindowRecursive, second)
        first.unbindFromParent()
        workspace.normalizeContainers()
        XCTAssertEqual(workspace.rootTilingContainer.children, [second])
        second.unbindFromParent()
        workspace.normalizeContainers()
        XCTAssertTrue(workspace.rootTilingContainer.children.isEmpty)
    }

    func testNormalizationRestoresBinaryTreeAndFocus() {
        let workspace = Workspace.get(byName: name)
        let windows = (1 ... 5).map { TestWindow.new(id: UInt32($0), parent: workspace.rootTilingContainer) }
        windows[1].markAsMostRecentChild()
        config.enableNormalizationOppositeOrientationForNestedContainers = true
        workspace.normalizeContainers()
        func checkBinary(_ container: TilingContainer) {
            XCTAssertLessThanOrEqual(container.children.count, 2)
            for child in container.children {
                if let child = child as? TilingContainer { checkBinary(child) }
            }
        }
        checkBinary(workspace.rootTilingContainer)
        XCTAssertEqual(workspace.rootTilingContainer.allLeafWindowsRecursive, windows)
        XCTAssertEqual(workspace.rootTilingContainer.mostRecentWindowRecursive, windows[1])
    }

    func testMovingToWorkspaceSplitsDestinationTile() {
        let source = Workspace.get(byName: name)
        let destination = Workspace.get(byName: name + "-destination")
        let moving = insert(1, into: source)
        let first = insert(2, into: destination)
        let second = insert(3, into: destination)
        XCTAssertEqual(moveWindowToWorkspace(moving, destination, CmdIoImpl.emptyStdinIgnoringOut, focusFollowsWindow: false, failIfNoop: false), .succ)
        destination.normalizeContainers()
        source.normalizeContainers()
        XCTAssertEqual((second.parent as! TilingContainer).children, [second, moving])
        XCTAssertEqual(destination.rootTilingContainer.children.first, first)
        XCTAssertTrue(source.isEffectivelyEmpty)
    }

    func testFloatingFocusDoesNotReplaceTiledInsertionTarget() {
        let workspace = Workspace.get(byName: name)
        let tiled = insert(1, into: workspace)
        let floating = TestWindow.new(id: 2, parent: workspace.floatingWindowsContainer)
        let new = insert(3, into: workspace)
        XCTAssertEqual(workspace.rootTilingContainer.children, [tiled, new])
        XCTAssertTrue(floating.parent === workspace.floatingWindowsContainer)
    }

    func testDisabledModeKeepsSiblingInsertion() {
        config.enableDwindleTiling = false
        let workspace = Workspace.get(byName: name)
        let windows = (1 ... 3).map { insert(UInt32($0), into: workspace) }
        XCTAssertEqual(workspace.rootTilingContainer.children, windows)
    }

    func testAccordionKeepsItsLayout() {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.layout = .accordion
        let windows = (1 ... 3).map { insert(UInt32($0), into: workspace) }
        XCTAssertEqual(workspace.rootTilingContainer.layout, .accordion)
        XCTAssertEqual(workspace.rootTilingContainer.children, windows)
    }

    func testResizeAndDirectionalFocusInNestedSplits() async {
        let workspace = Workspace.get(byName: name)
        let first = insert(1, into: workspace)
        let second = insert(2, into: workspace)
        let third = insert(3, into: workspace)
        let split = second.parent as! TilingContainer
        XCTAssertEqual(split.orientation, .v)
        let resize = ResizeCommand(args: ResizeCmdArgs(rawArgs: [], dimension: .height, units: .add(1)))
        XCTAssertEqual(resize.run(.defaultEnv.withWindowId(third.windowId), CmdIoImpl.emptyStdinIgnoringOut), .succ)
        XCTAssertEqual(third.getWeight(.v), 2)
        XCTAssertEqual(second.getWeight(.v), 0)
        XCTAssertEqual(first.getWeight(.h), 1)
        XCTAssertTrue(third.focusWindow())
        let focusResult = await FocusCommand.new(direction: .up).run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(focusResult.exitCode.rawValue, 0)
        XCTAssertEqual(focus.windowOrNil, second)
    }

    func testNormalizationPreservesSameOrientationSplits() {
        let workspace = Workspace.get(byName: name)
        workspace.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 2400, height: 500)
        let first = insert(1, into: workspace)
        first.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 2000, height: 500)
        let second = insert(2, into: workspace)
        second.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 1000, topLeftY: 0, width: 1000, height: 500)
        insert(3, into: workspace)
        config.enableNormalizationOppositeOrientationForNestedContainers = true
        workspace.normalizeContainers()
        XCTAssertEqual(workspace.rootTilingContainer.orientation, .h)
        XCTAssertEqual((second.parent as! TilingContainer).orientation, .h)
    }

    func testThirdWindowUsesCurrentTileSizeBeforeSecondHasBeenLaidOut() {
        let workspace = Workspace.get(byName: name)
        let first = insert(1, into: workspace)
        first.lastAppliedLayoutPhysicalRect = workspace.lastAppliedLayoutPhysicalRect
        let second = insert(2, into: workspace)
        XCTAssertNil(second.lastAppliedLayoutPhysicalRect)
        // The old root rectangle is wider than it is tall, but the second window's
        // current tile occupies half of that width, so the third must split vertically.
        workspace.rootTilingContainer.lastAppliedLayoutPhysicalRect = workspace.lastAppliedLayoutPhysicalRect
        let third = insert(3, into: workspace)
        XCTAssertEqual((second.parent as! TilingContainer).orientation, .v)
        XCTAssertEqual((second.parent as! TilingContainer).children, [second, third])
    }

    func testRemovingEmptyBranchCollapsesItsParentInOnePass() {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        _ = TilingContainer.newHTiles(parent: root, adaptiveWeight: 1)
        let liveSplit = TilingContainer.newVTiles(parent: root, adaptiveWeight: 1)
        let first = TestWindow.new(id: 1, parent: liveSplit)
        let second = TestWindow.new(id: 2, parent: liveSplit)
        workspace.normalizeContainers()
        XCTAssertTrue(workspace.rootTilingContainer === liveSplit)
        XCTAssertEqual(workspace.rootTilingContainer.children, [first, second])
    }

    func testSampleConfigurationParses() throws {
        let url = projectRoot.appending(path: "docs/config-examples/hyprspace-dwindle.toml")
        let result = parseConfig(try String(contentsOf: url, encoding: .utf8))
        XCTAssertTrue(result.errors.isEmpty, "\(result.errors)")
        XCTAssertTrue(result.config.enableDwindleTiling)
        let bindings = result.config.modes[mainModeId]!.bindings.values
        XCTAssertFalse(bindings.isEmpty)
        XCTAssertTrue(bindings.allSatisfy { $0.modifiers.contains(.control) && !$0.modifiers.contains(.option) })
    }

    func testConfigOptionIsOptInAndRequiresBoolean() {
        XCTAssertFalse(parseConfig("").config.enableDwindleTiling)
        let enabled = parseConfig("enable-dwindle-tiling = true")
        XCTAssertTrue(enabled.errors.isEmpty)
        XCTAssertTrue(enabled.config.enableDwindleTiling)
        XCTAssertFalse(parseConfig("enable-dwindle-tiling = 'true'").errors.isEmpty)
    }
}
