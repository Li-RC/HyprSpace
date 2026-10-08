@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class WorkspaceStatusTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        TrayMenuModel.shared.isEnabled = true
    }

    func testSnapshotIncludesOccupiedAndCurrentSpacesInNaturalOrder() {
        let snapshot = Snapshot(spaces: ["1", "2", "3", "10"], current: "3", windows: [
            AppWindow(id: 1, app: "Zebra", bundle: "z", title: "", workspace: "10"),
            AppWindow(id: 2, app: "Alpha", bundle: "a", title: "", workspace: "2"),
            AppWindow(id: 3, app: "Alpha", bundle: "a", title: "", workspace: "2"),
            AppWindow(id: 4, app: "Zebra", bundle: "z", title: "", workspace: "2"),
        ])
        XCTAssertEqual(snapshot.menuSpaces, ["2", "3", "10"])
        XCTAssertEqual(snapshot.occupiedSpaces, ["2", "10"])
        XCTAssertEqual(snapshot.appBundles(in: "2"), ["a", "z"])
    }

    func testTreeAdapterIncludesHiddenGroupMembersAndRemovesClosedWindows() {
        let workspace = Workspace.get(byName: "1")
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let second = TestWindow.new(id: 2, parent: group)
        XCTAssertTrue(second.focusWindow())
        let model = WorkspaceModel()
        var updates = 0
        model.changed = { updates += 1 }
        model.updateFromTree()
        XCTAssertEqual(Set(model.snapshot.windows.map(\.id)), [1, 2])
        XCTAssertTrue(first.isInactiveGroupMember)
        XCTAssertEqual(model.snapshot.appBundles(in: "1"), [TestApp.shared.rawAppBundleId!])
        model.updateFromTree()
        XCTAssertEqual(updates, 1)
        first.unbindFromParent()
        model.updateFromTree()
        XCTAssertEqual(model.snapshot.windows.map(\.id), [2])
        XCTAssertEqual(updates, 2)
    }

    func testNavigationUsesNativeFocusHistoryAndCommandsAcrossWorkspaces() async {
        let one = Workspace.get(byName: "1")
        let two = Workspace.get(byName: "2")
        let first = TestWindow.new(id: 1, parent: one.rootTilingContainer)
        let second = TestWindow.new(id: 2, parent: one.rootTilingContainer)
        let other = TestWindow.new(id: 3, parent: two.rootTilingContainer)
        let model = WorkspaceModel()
        XCTAssertTrue(second.focusWindow())
        model.updateFromTree()
        XCTAssertTrue(first.focusWindow())
        model.updateFromTree()
        XCTAssertTrue(other.focusWindow())
        model.updateFromTree()
        let bundle = TestApp.shared.rawAppBundleId!
        XCTAssertEqual(model.navigationArguments(to: "1", appBundle: bundle), ["workspace", "1"])
        let arguments = model.navigationArguments(to: "1", appBundle: bundle, focusApp: true)!
        XCTAssertEqual(arguments, ["focus", "--window-id", "1"])
        let result = await parseCommand(arguments).cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode.rawValue, 0)
        XCTAssertEqual(focus.windowOrNil, first)
        model.updateFromTree()
        XCTAssertNil(model.navigationArguments(to: "1"))
        XCTAssertNil(model.navigationArguments(to: "1", appBundle: "missing"))
        XCTAssertEqual(model.navigationArguments(to: "1", appBundle: bundle), arguments)
    }

    func testOverviewCommandSelectsInactiveGroupMember() async {
        let workspace = Workspace.get(byName: "1")
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let second = TestWindow.new(id: 2, parent: group)
        XCTAssertTrue(second.focusWindow())
        let model = WorkspaceModel()
        model.updateFromTree()
        let hidden = model.snapshot.windows.first { $0.id == 1 }!
        let result = await parseCommand(["focus", "--window-id", String(hidden.id)]).cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode.rawValue, 0)
        XCTAssertEqual(group.mostRecentWindowRecursive, first)
        XCTAssertFalse(first.isInactiveGroupMember)
    }

    func testClosedOverviewTargetFailsWithoutChangingFocus() async {
        let workspace = Workspace.get(byName: "1")
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let second = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        XCTAssertTrue(second.focusWindow())
        first.unbindFromParent()
        TestApp.shared.windows = [second]
        let result = await parseCommand(["focus", "--window-id", "1"]).cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertNotEqual(result.exitCode.rawValue, 0)
        XCTAssertEqual(focus.windowOrNil, second)
    }

    func testPlacementCentersWorkspacesAndFallsBackForCrowdingAndNotches() {
        let screen = NSRect(x: -1000, y: 0, width: 1000, height: 800)
        let native = NSRect(x: -100, y: 778, width: 80, height: 22)
        func frame(notch: Bool = false, menuEnd: CGFloat = -800, statusStart: CGFloat = -100) -> NSRect? {
            menuStripFrame(screen: screen, hasNotch: notch, native: native, menuEnd: menuEnd,
                           statusStart: statusStart, width: 124, workspaceWidth: 100, height: 22)
        }
        XCTAssertEqual(frame()?.minX, -552)
        XCTAssertEqual(frame(notch: true), native)
        XCTAssertEqual(frame(menuEnd: -200, statusStart: -100)?.width, 84)
        XCTAssertNil(frame(menuEnd: -100, statusStart: -100))
    }

    func testOverviewFitsSmallDisplays() {
        let visible = NSRect(x: 0, y: 0, width: 500, height: 300)
        let anchor = NSRect(x: 220, y: 300, width: 24, height: 22)
        let size = overviewSize(visibleFrame: visible, anchor: anchor, contentHeight: 1000)
        XCTAssertEqual(size.height, 252)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertLessThan(size.width, visible.width)
    }

    func testSettingsPersistAndNotifyOnlyOnChanges() {
        let suite = "HyprSpace.WorkspaceStatusTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.menuBarPosition, .automatic)
        XCTAssertTrue(settings.dockBadgesEnabled)
        XCTAssertFalse(settings.compactViewEnabled)
        var changes = 0
        settings.changed = { changes += 1 }
        settings.menuBarPosition = .system
        settings.dockBadgesEnabled = false
        settings.compactViewEnabled = true
        settings.compactViewEnabled = true
        XCTAssertEqual(changes, 3)
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.menuBarPosition, .system)
        XCTAssertFalse(reloaded.dockBadgesEnabled)
        XCTAssertTrue(reloaded.compactViewEnabled)
    }
}
