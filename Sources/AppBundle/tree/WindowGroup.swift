import Common

extension Window {
    var windowGroup: TilingContainer? {
        guard let parent = parent as? TilingContainer, parent.isWindowGroup else { return nil }
        return parent
    }

    var isInactiveGroupMember: Bool {
        windowGroup.map { $0.mostRecentWindowRecursive != self } ?? false
    }

    @MainActor @discardableResult
    func createWindowGroup() -> TilingContainer {
        if let group = windowGroup { return group }
        let binding = unbindFromParent()
        let group = TilingContainer(parent: binding.parent, adaptiveWeight: binding.adaptiveWeight, .h, .tiles, index: binding.index)
        group.isWindowGroup = true
        bind(to: group, adaptiveWeight: 1, index: 0)
        return group
    }

    @MainActor
    func removeFromWindowGroup() {
        guard let group = windowGroup, let workspace = group.nodeWorkspace else { return }
        if group.isRootContainer {
            group.unbindFromParent()
            let root = TilingContainer(parent: workspace, adaptiveWeight: WEIGHT_AUTO, group.orientation, .tiles, index: 0)
            group.bind(to: root, adaptiveWeight: 1, index: 0)
        }
        guard let parent = group.parent as? TilingContainer, let index = group.ownIndex else { return }
        bind(to: parent, adaptiveWeight: WEIGHT_AUTO, index: index + 1)
    }
}
