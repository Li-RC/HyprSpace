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
        var drag = GroupTabDrag(windowId: 1, origin: CGPoint(x: 50, y: 16), originalIndex: 0)
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

    func testDraggedTabFollowsPointerAndClampsAtBarEdges() {
        let bounds = NSRect(x: 0, y: 0, width: 300, height: windowGroupBarHeight)
        var drag = GroupTabDrag(windowId: 1, origin: CGPoint(x: 150, y: 16), originalIndex: 1)
        drag.update(at: CGPoint(x: 175, y: 16), in: bounds, memberCount: 3)
        XCTAssertEqual(drag.tabOriginX(in: bounds, memberCount: 3), 125)
        drag.update(at: CGPoint(x: 1000, y: 16), in: bounds, memberCount: 3)
        XCTAssertEqual(drag.tabOriginX(in: bounds, memberCount: 3), 200)
        drag.update(at: CGPoint(x: -1000, y: 16), in: bounds, memberCount: 3)
        XCTAssertEqual(drag.tabOriginX(in: bounds, memberCount: 3), 0)
    }

    func testTabViewsRetainIdentityAcrossReorderingAndBarResize() {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let second = TestWindow.new(id: 2, parent: group)
        let view = DecorationView(frame: NSRect(x: 0, y: 0, width: 300, height: windowGroupBarHeight))
        view.updateGroup(group)
        let tabs = view.subviews.compactMap { $0 as? GroupTabView }
        let firstTab = tabs[0]
        let secondTab = tabs[1]
        XCTAssertTrue(group.reorderWindowGroupMember(first.windowId, to: 1))
        view.updateGroup(group)
        XCTAssertTrue(view.subviews.contains { $0 === firstTab })
        XCTAssertTrue(view.subviews.contains { $0 === secondTab })
        XCTAssertEqual(firstTab.frame.minX, 150)
        XCTAssertEqual(secondTab.frame.minX, 0)
        view.setFrameSize(NSSize(width: 600, height: windowGroupBarHeight))
        XCTAssertEqual(firstTab.frame.minX, 300)
        XCTAssertEqual(firstTab.frame.width, 300)
        XCTAssertEqual(view.memberIds, [second.windowId, first.windowId])
    }

    func testMouseDragMovesTabContinuouslyAndReleaseSettlesIntoSlot() {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let second = TestWindow.new(id: 2, parent: group)
        let third = TestWindow.new(id: 3, parent: group)
        let view = DecorationView(frame: NSRect(x: 0, y: 0, width: 300, height: windowGroupBarHeight))
        let panel = NSPanel(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        panel.contentView = view
        defer { panel.close() }
        view.updateGroup(group)
        let tab = view.subviews.compactMap { $0 as? GroupTabView }[0]
        func event(_ type: NSEvent.EventType, x: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 16), modifierFlags: [.control], timestamp: 0,
                              windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: event(.leftMouseDown, x: 50))
        view.mouseDragged(with: event(.leftMouseDragged, x: 175))
        XCTAssertEqual(tab.frame.minX, 125)
        XCTAssertEqual(group.children, [second, first, third])
        // Repeated refreshes must preserve the pointer offset rather than snapping
        // the dragged tab to the slot selected by the current group order.
        view.updateGroup(group)
        XCTAssertEqual(tab.frame.minX, 125)
        view.mouseUp(with: event(.leftMouseUp, x: 175))
        XCTAssertEqual(tab.frame.minX, 100)
        XCTAssertEqual(group.children, [second, first, third])
    }

    func testDraggingUpdatesTreeAndDisplayedOrderBeforeRelease() {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let second = TestWindow.new(id: 2, parent: group)
        let third = TestWindow.new(id: 3, parent: group)
        XCTAssertTrue(second.focusWindow())
        let history = Array(group.mruChildren)
        let view = DecorationView()
        let bounds = NSRect(x: 0, y: 0, width: 300, height: windowGroupBarHeight)
        var drag = GroupTabDrag(windowId: first.windowId, origin: CGPoint(x: 50, y: 16), originalIndex: 0)
        for (x, expected) in [(150.0, [second, first, third]), (250.0, [second, third, first]), (50.0, [first, second, third])] {
            drag.update(at: CGPoint(x: x, y: 16), in: bounds, memberCount: 3)
            XCTAssertTrue(drag.apply(in: group))
            view.updateGroup(group)
            XCTAssertEqual(group.children, expected)
            XCTAssertEqual(view.memberIds, expected.map(\.windowId))
            XCTAssertEqual(view.activeIndex, second.ownIndex)
            XCTAssertEqual(focus.windowOrNil, second)
            XCTAssertEqual(Array(group.mruChildren), history)
        }
    }

    func testOutsideReleaseRestoresOriginalOrderAfterLiveReordering() {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let second = TestWindow.new(id: 2, parent: group)
        let third = TestWindow.new(id: 3, parent: group)
        XCTAssertTrue(third.focusWindow())
        let bounds = NSRect(x: 0, y: 0, width: 300, height: windowGroupBarHeight)
        var drag = GroupTabDrag(windowId: second.windowId, origin: CGPoint(x: 150, y: 16), originalIndex: 1)
        drag.update(at: CGPoint(x: 250, y: 16), in: bounds, memberCount: 3)
        XCTAssertTrue(drag.apply(in: group))
        XCTAssertEqual(group.children, [first, third, second])
        drag.update(at: CGPoint(x: 250, y: -10), in: bounds, memberCount: 3)
        XCTAssertFalse(drag.apply(in: group))
        XCTAssertTrue(drag.cancel(in: group))
        XCTAssertEqual(group.children, [first, second, third])
        XCTAssertEqual(focus.windowOrNil, third)
        third.unbindFromParent()
        second.unbindFromParent()
        XCTAssertFalse(drag.cancel(in: group))
        XCTAssertEqual(group.children, [first])
    }


    func testPlainDragDoesNotReorderAndReleasingControlCancelsReorder() {
        for flags: NSEvent.ModifierFlags in [[], [.control]] {
            setUpWorkspacesForTests()
            TrayMenuModel.shared.isEnabled = true
            let workspace = Workspace.get(byName: name)
            let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
            let group = first.createWindowGroup()
            let second = TestWindow.new(id: 2, parent: group)
            XCTAssertTrue(second.focusWindow())
            let view = DecorationView(frame: NSRect(x: 0, y: 0, width: 300, height: windowGroupBarHeight))
            let panel = NSPanel(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            panel.contentView = view
            view.updateGroup(group)
            func event(_ type: NSEvent.EventType, x: CGFloat, flags: NSEvent.ModifierFlags) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 16), modifierFlags: flags, timestamp: 0,
                                  windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            view.mouseDown(with: event(.leftMouseDown, x: 50, flags: flags))
            view.mouseDragged(with: event(.leftMouseDragged, x: 250, flags: flags))
            XCTAssertEqual(group.children, flags.contains(.control) ? [second, first] : [first, second])
            view.mouseUp(with: event(.leftMouseUp, x: 250, flags: []))
            XCTAssertEqual(group.children, [first, second])
            XCTAssertEqual(focus.windowOrNil, second)
            panel.close()
        }
    }

    func testGlassSurfaceRemainsVisibleDuringControlDrag() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Glass requires macOS 26") }
        TrayMenuModel.shared.isEnabled = true
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let group = first.createWindowGroup()
        let second = TestWindow.new(id: 2, parent: group)
        XCTAssertTrue(second.focusWindow())
        let bar = GroupBarView()
        bar.frame = NSRect(x: 0, y: 0, width: 300, height: windowGroupBarHeight)
        bar.layoutSubtreeIfNeeded()
        let panel = NSPanel(contentRect: bar.frame, styleMask: .borderless, backing: .buffered, defer: false)
        panel.contentView = bar
        defer { panel.close() }
        let view = bar.tabs
        view.updateGroup(group)
        let glass = try XCTUnwrap(bar.background as? NSGlassEffectView)
        XCTAssertTrue(glass.contentView === view)
        XCTAssertFalse(glass.isHidden)
        func event(_ type: NSEvent.EventType, x: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 16), modifierFlags: [.control], timestamp: 0,
                              windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: event(.leftMouseDown, x: 50))
        view.mouseDragged(with: event(.leftMouseDragged, x: 250))
        XCTAssertEqual(group.children, [second, first])
        XCTAssertFalse(bar.background.isHidden)
        view.mouseUp(with: event(.leftMouseUp, x: 250))
        XCTAssertFalse(bar.background.isHidden)
        XCTAssertEqual(view.activeIndex, 0)
        XCTAssertEqual(focus.windowOrNil, second)
    }

    func testFirstGestureReordersWithoutSelectingTabIncludingControlClickRouting() throws {
        for controlAtMouseDown in [true, false] {
            setUpWorkspacesForTests()
            TrayMenuModel.shared.isEnabled = true
            let workspace = Workspace.get(byName: name)
            let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
            let group = first.createWindowGroup()
            let second = TestWindow.new(id: 2, parent: group)
            XCTAssertTrue(second.focusWindow())
            let bar = GroupBarView()
            bar.frame = NSRect(x: 0, y: 0, width: 300, height: windowGroupBarHeight)
            let panel = NSPanel(contentRect: bar.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.contentView = bar
            bar.layoutSubtreeIfNeeded()
            let view = bar.tabs
            view.updateGroup(group)
            bar.applyContrast(.dark)
            XCTAssertTrue(bar.hitTest(CGPoint(x: 50, y: 16)) === view)
            func event(_ type: NSEvent.EventType, x: CGFloat, flags: NSEvent.ModifierFlags) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 16), modifierFlags: flags, timestamp: 0,
                                  windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            if controlAtMouseDown {
                view.rightMouseDown(with: event(.rightMouseDown, x: 50, flags: [.control]))
                view.rightMouseDragged(with: event(.rightMouseDragged, x: 250, flags: [.control]))
            } else {
                view.mouseDown(with: event(.leftMouseDown, x: 50, flags: []))
                view.mouseDragged(with: event(.leftMouseDragged, x: 250, flags: [.control]))
            }
            XCTAssertEqual(group.children, [second, first])
            XCTAssertEqual(focus.windowOrNil, second)
            if #available(macOS 27.0, *) {
                let movingTabs = view.subviews.compactMap { $0 as? GroupTabView }
                XCTAssertEqual(movingTabs.count, 2)
                for tab in movingTabs {
                    XCTAssertFalse(tab.isHidden)
                    XCTAssertEqual(tab.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
                }
            }
            if controlAtMouseDown { view.rightMouseUp(with: event(.rightMouseUp, x: 250, flags: [.control])) }
            else { view.mouseUp(with: event(.leftMouseUp, x: 250, flags: [.control])) }
            XCTAssertEqual(group.children, [second, first])
            panel.close()
        }
    }
}
