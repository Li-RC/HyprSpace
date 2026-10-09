import AppKit
import Common

@MainActor
private var moveWithMouseTask: Task<(), any Error>? = nil

@MainActor
private var draggedWindowId: UInt32? = nil

@MainActor private var mouseDownPoint: CGPoint?
@MainActor private var mouseDownRects: [UInt32: Rect] = [:]
@MainActor private var resizingWindowIds: Set<UInt32> = []

func isWindowEdgeDrag(at point: CGPoint, in rect: Rect) -> Bool {
    let frame = CGRect(origin: rect.topLeftCorner, size: rect.size)
    return frame.insetBy(dx: -8, dy: -8).contains(point) && !frame.insetBy(dx: 8, dy: 8).contains(point)
}

@MainActor
func beginWindowMouseGesture(at point: CGPoint) {
    mouseDownPoint = point
    mouseDownRects.removeAll()
    resizingWindowIds.removeAll()
    draggedWindowId = nil
}

@MainActor
func recordWindowMouseResize(_ windowId: UInt32) {
    resizingWindowIds.insert(windowId)
    if draggedWindowId == windowId { draggedWindowId = nil }
    DwindleDropPreview.shared.hide()
}

@MainActor
private func isWindowResizeGesture(_ window: Window, rect: Rect?) -> Bool {
    if resizingWindowIds.contains(window.windowId) { return true }
    guard let point = mouseDownPoint, let rect = mouseDownRects[window.windowId] ?? rect else { return false }
    mouseDownRects[window.windowId] = rect
    return isWindowEdgeDrag(at: point, in: rect)
}

@MainActor
func recordDwindleMouseMove(_ window: Window, from previous: Rect, to current: Rect, mouseButtonDown: Bool) {
    guard config.enableDwindleTiling, mouseButtonDown,
          window.isFloating || window.parent is TilingContainer,
          currentlyManipulatedWithMouseWindowId == nil || currentlyManipulatedWithMouseWindowId == window.windowId else { return }
    if isWindowResizeGesture(window, rect: previous) ||
        abs(current.width - previous.width) >= 2 || abs(current.height - previous.height) >= 2 {
        recordWindowMouseResize(window.windowId)
        return
    }
    guard current.topLeftCorner != previous.topLeftCorner else { return }
    draggedWindowId = window.windowId
    currentlyManipulatedWithMouseWindowId = window.windowId
    window.lastAppliedLayoutPhysicalRect = nil
}

func movedObs(_: AXObserver, ax: AXUIElement, notif: CFString, _: UnsafeMutableRawPointer?) {
    let windowId = ax.containingWindowId()
    let notif = notif as String
    Task.startUnstructured { @MainActor in
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        // Native dwindle drags only choose a drop target on release. Avoid two
        // complete AX model refreshes for every mouse-move notification.
        if config.enableDwindleTiling, isLeftMouseButtonDown,
           let windowId, let window = Window.get(byId: windowId),
           focus.windowOrNil == window,
           let current = nativeDecorationOwnerRect(windowId) {
            recordDwindleMouseMove(window, from: window.lastAppliedLayoutPhysicalRect ?? current,
                                  to: current, mouseButtonDown: true)
            WindowDecorations.shared.captureMouseDrag(windowId: windowId)
            updateDwindleDragPreview(at: mouseLocation)
            return
        }
        guard let windowId, let window = Window.get(byId: windowId), try await isManipulatedWithMouse(window) else {
            scheduleCancellableCompleteRefreshSession(.ax(notif))
            return
        }
        moveWithMouseTask?.cancel()
        moveWithMouseTask = Task.startUnstructured {
            try checkCancellation()
            try await runLightSession(.ax(notif), token) {
                if isLeftMouseButtonDown { try await moveWithMouse(window) }
            }
        }
    }
}

@MainActor
private func moveWithMouse(_ window: Window) async throws { // todo cover with tests
    resetClosedWindowsCache()
    switch window.windowParentCases {
        case .floatingWindowsContainer:
            draggedWindowId = window.windowId
            try await moveFloatingWindow(window)
        case .macosFullscreenWindowsContainer, .macosMinimizedWindowsContainer, .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
            return // Unconventional windows can't be moved with mouse
        case .tilingContainer:
            moveTilingWindow(window)
        case .unbound: return
    }
}

@MainActor
private func moveFloatingWindow(_ window: Window) async throws {
    guard let targetWorkspace = try await window.getCenter(.cancellable)?.monitorApproximation.activeWorkspace else { return }
    guard let parent = window.parent else { return }
    if targetWorkspace != parent {
        window.bindAsFloatingWindow(to: targetWorkspace)
    }
}

@MainActor
private func moveTilingWindow(_ window: Window) {
    if isWindowResizeGesture(window, rect: window.lastAppliedLayoutPhysicalRect) { return }
    draggedWindowId = window.windowId
    currentlyManipulatedWithMouseWindowId = window.windowId
    window.lastAppliedLayoutPhysicalRect = nil
    // Dwindle drops choose a split on release. Keep the tree stable while
    // crossing other tiles so the target does not keep changing underneath us.
    if config.enableDwindleTiling { return }
    let mouseLocation = mouseLocation
    let targetWorkspace = mouseLocation.monitorApproximation.activeWorkspace
    let swapTarget = mouseLocation
        .findWindowRecursively(in: targetWorkspace.rootTilingContainer, virtual: false, fullscreenCoversAll: false)?
        .takeIf { $0 != window }
    // Group membership changes on mouse release, rather than swapping its active
    // member while the dragged window is passing over the group.
    if window.windowGroup?.lastAppliedLayoutPhysicalRect?.contains(mouseLocation) == true { return }
    if swapTarget?.windowGroup != nil { return }
    window.removeFromWindowGroup()
    if targetWorkspace != window.nodeWorkspace { // Move window to a different monitor
        let index: Int = if let swapTarget, let parent = swapTarget.parent as? TilingContainer, let targetRect = swapTarget.lastAppliedLayoutPhysicalRect {
            mouseLocation.getProjection(parent.orientation) >= targetRect.center.getProjection(parent.orientation)
                ? swapTarget.ownIndex.orDie() + 1
                : swapTarget.ownIndex.orDie()
        } else {
            0
        }
        window.bind(
            to: swapTarget?.parent ?? targetWorkspace.rootTilingContainer,
            adaptiveWeight: WEIGHT_AUTO,
            index: index,
        )
    } else if let swapTarget {
        swapWindows(mruDominant: window, swapTarget)
    }
}

@MainActor
@discardableResult
func finishMovingWindowWithMouse(at point: CGPoint) -> Bool {
    moveWithMouseTask?.cancel()
    moveWithMouseTask = nil
    defer {
        draggedWindowId = nil
        mouseDownPoint = nil
        mouseDownRects.removeAll()
        resizingWindowIds.removeAll()
        DwindleDropPreview.shared.hide()
    }
    guard let id = draggedWindowId, let window = Window.get(byId: id),
          !window.isFloating,
          !isWindowResizeGesture(window, rect: window.lastAppliedLayoutPhysicalRect) else { return false }
    let workspace = point.monitorApproximation.activeWorkspace
    return config.enableDwindleTiling
        ? dropDwindleWindow(window, at: point, in: workspace)
        : joinWindowToGroupUnderMouse(window, at: point, in: workspace)
}

// Side bands take precedence over top/bottom, so wide tiles still have easy
// horizontal drop zones near their title bars. Accept the narrow border gap too.
func dwindleDropDirection(at point: CGPoint, in rect: Rect) -> CardinalDirection? {
    guard rect.width > 0, rect.height > 0,
          point.x >= rect.minX - 12, point.x <= rect.maxX + 12,
          point.y >= rect.minY - 12, point.y <= rect.maxY + 12 else { return nil }
    let x = (point.x - rect.minX) / rect.width
    if x <= 0.25 { return .left }
    if x >= 0.75 { return .right }
    return point.y < rect.center.y ? .up : .down
}

struct DwindleDropTarget {
    let window: Window
    let direction: CardinalDirection? // nil joins a group
    let previewRect: Rect
}

func dwindleSplitPreviewRect(_ rect: Rect, direction: CardinalDirection) -> Rect {
    switch direction {
        case .left: Rect(topLeftX: rect.minX, topLeftY: rect.minY, width: rect.width / 2, height: rect.height)
        case .right: Rect(topLeftX: rect.center.x, topLeftY: rect.minY, width: rect.width / 2, height: rect.height)
        case .up: Rect(topLeftX: rect.minX, topLeftY: rect.minY, width: rect.width, height: rect.height / 2)
        case .down: Rect(topLeftX: rect.minX, topLeftY: rect.center.y, width: rect.width, height: rect.height / 2)
    }
}

@MainActor
func dwindleDropTarget(_ window: Window, at point: CGPoint, in workspace: Workspace) -> DwindleDropTarget? {
    var nearest: (window: Window, rect: Rect, distance: CGFloat)?
    for candidate in workspace.rootTilingContainer.allLeafWindowsRecursive {
        guard !candidate.isInactiveGroupMember, !candidate.isFullscreen,
              candidate != window || candidate.windowGroup?.children.count ?? 0 > 1,
              let rect = (candidate.windowGroup ?? candidate).lastAppliedLayoutPhysicalRect else { continue }
        let distance = max(max(rect.minX - point.x, point.x - rect.maxX, 0),
                           max(rect.minY - point.y, point.y - rect.maxY, 0))
        if distance <= 12 && (nearest == nil || distance < nearest!.distance) {
            nearest = (candidate, rect, distance)
        }
    }
    guard let target = nearest else { return nil }
    if let group = target.window.windowGroup {
        let onBar = target.rect.contains(point) && point.y < target.rect.minY + windowGroupBarHeight
        let inCenter = abs(point.x - target.rect.center.x) < target.rect.width / 4 && abs(point.y - target.rect.center.y) < target.rect.height / 4
        if onBar || inCenter {
            return group == window.windowGroup ? nil : DwindleDropTarget(window: target.window, direction: nil, previewRect: target.rect)
        }
    }
    guard let direction = dwindleDropDirection(at: point, in: target.rect) else { return nil }
    // Removing the source can collapse its old split. Preview the expanded
    // target area in that case, including changing two stacked tiles to columns.
    var tile: TreeNode = target.window.windowGroup ?? target.window
    var rect = target.rect
    while let parent = tile.parent as? TilingContainer, !parent.isWindowGroup {
        let siblings = parent.children.filter { $0 != tile }
        guard siblings.isEmpty || (siblings.count == 1 && siblings[0].allLeafWindowsRecursive == [window]) else { break }
        rect = parent.lastAppliedLayoutPhysicalRect ?? rect
        tile = parent
    }
    return DwindleDropTarget(window: target.window, direction: direction,
                             previewRect: dwindleSplitPreviewRect(rect, direction: direction))
}

@MainActor
func updateDwindleDragPreview(at point: CGPoint) {
    guard isLeftMouseButtonDown, let id = draggedWindowId, let window = Window.get(byId: id), !window.isFloating else {
        DwindleDropPreview.shared.hide()
        return
    }
    let target = dwindleDropTarget(window, at: point, in: point.monitorApproximation.activeWorkspace)
    DwindleDropPreview.shared.show(target?.previewRect)
}

@MainActor
@discardableResult
func dropDwindleWindow(_ window: Window, at point: CGPoint, in workspace: Workspace) -> Bool {
    guard window.isFloating || window.parent is TilingContainer else { return false }
    guard let target = dwindleDropTarget(window, at: point, in: workspace) else {
        guard workspace != window.nodeWorkspace, workspace.rootTilingContainer.allLeafWindowsRecursive.isEmpty else { return false }
        resetClosedWindowsCache()
        window.isFullscreen = false
        window.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: 0)
        _ = window.focusWindow()
        return true
    }
    guard let direction = target.direction else {
        return joinWindowToGroupUnderMouse(window, at: point, in: workspace)
    }
    let tile: TreeNode = target.window.windowGroup ?? target.window
    resetClosedWindowsCache()
    window.isFullscreen = false
    window.unbindFromParent()
    let binding = tile.unbindFromParent()
    let split = TilingContainer(parent: binding.parent, adaptiveWeight: binding.adaptiveWeight,
                                direction.orientation, .tiles, index: binding.index)
    tile.bind(to: split, adaptiveWeight: 1, index: 0)
    window.bind(to: split, adaptiveWeight: 1, index: direction.isPositive ? 1 : 0)
    _ = window.focusWindow()
    return true
}

@MainActor
@discardableResult
func joinWindowToGroupUnderMouse(_ window: Window, at point: CGPoint, in workspace: Workspace) -> Bool {
    guard window.isFloating || window.parent is TilingContainer,
          let target = point.findWindowRecursively(in: workspace.rootTilingContainer, virtual: false, fullscreenCoversAll: false),
          let group = target.windowGroup, group != window.windowGroup,
          !target.isFullscreen else { return false }
    resetClosedWindowsCache()
    window.isFullscreen = false
    window.bind(to: group, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    window.markAsMostRecentChild()
    return true
}

@MainActor
func swapWindows(mruDominant window1: Window, _ window2: Window) {
    if window1 == window2 { return }

    let binding2 = window2.unbindFromParent()
    let binding1 = window1.unbindFromParent()

    window2.bind(to: binding1.parent, adaptiveWeight: binding1.adaptiveWeight, index: binding1.index)
    window1.bind(to: binding2.parent, adaptiveWeight: binding2.adaptiveWeight, index: binding2.index)
}

extension CGPoint {
    @MainActor
    func findWindowRecursively(
        in tree: TilingContainer,
        virtual: Bool,
        fullscreenCoversAll: Bool,
    ) -> Window? {
        if fullscreenCoversAll {
            if let window = tree.mostRecentWindowRecursive, window.isFullscreen {
                return window
            }
        }
        return _findWindowRecursively(in: tree, virtual: virtual)
    }

    @MainActor
    private func _findWindowRecursively(in tree: TilingContainer, virtual: Bool) -> Window? {
        let point = self
        if tree.isWindowGroup {
            let rect = virtual ? tree.lastAppliedLayoutVirtualRect : tree.lastAppliedLayoutPhysicalRect
            return rect?.contains(point) == true ? tree.mostRecentWindowRecursive : nil
        }
        let target: TreeNode? = switch tree.layout {
            case .tiles:
                tree.children.first(where: {
                    (virtual ? $0.lastAppliedLayoutVirtualRect : $0.lastAppliedLayoutPhysicalRect)?.contains(point) == true
                })
            case .accordion:
                tree.mostRecentChild
        }
        guard let target else { return nil }
        return switch target.tilingTreeNodeCasesOrDie() {
            case .window(let window): window
            case .tilingContainer(let container): _findWindowRecursively(in: container, virtual: virtual)
        }
    }
}
