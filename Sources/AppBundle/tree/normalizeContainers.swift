extension Workspace {
    @MainActor func normalizeContainers() {
        rootTilingContainer.unbindEmptyAndAutoFlatten() // Beware! rootTilingContainer may change after this line of code
        if config.enableDwindleTiling {
            rootTilingContainer.normalizeDwindle()
        } else if config.enableNormalizationOppositeOrientationForNestedContainers {
            rootTilingContainer.normalizeOppositeOrientationForNestedContainers()
        }
    }
}

extension TilingContainer {
    @MainActor fileprivate func unbindEmptyAndAutoFlatten() {
        for child in children {
            (child as? TilingContainer)?.unbindEmptyAndAutoFlatten()
        }
        if let child = children.singleOrNil(),
           (config.enableNormalizationFlattenContainers || (config.enableDwindleTiling && layout == .tiles)) &&
           (child is TilingContainer || !isRootContainer)
        {
            child.unbindFromParent()
            let mru = parent?.mostRecentChild
            let previousBinding = unbindFromParent()
            child.bind(to: previousBinding.parent, adaptiveWeight: previousBinding.adaptiveWeight, index: previousBinding.index)
            (child as? TilingContainer)?.unbindEmptyAndAutoFlatten()
            if mru != self {
                mru?.markAsMostRecentChild()
            } else {
                child.markAsMostRecentChild()
            }
        } else if children.isEmpty && !isRootContainer {
            unbindFromParent()
        }
    }

    // Moves and explicit layout commands can leave more than two siblings. Keep their order,
    // total weight, and focus while restoring binary splits.
    @MainActor fileprivate func normalizeDwindle() {
        let mru = mostRecentChild
        if layout == .tiles && children.count > 2 {
            let tail = Array(children.dropFirst())
            let weight = tail.reduce(0) { $0 + $1.getWeight(orientation) }
            tail.forEach { $0.unbindFromParent() }
            let split = TilingContainer(parent: self, adaptiveWeight: weight, orientation.opposite, .tiles, index: 1)
            for child in tail {
                child.bind(to: split, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
            }
        }
        for child in children {
            (child as? TilingContainer)?.normalizeDwindle()
        }
        mru?.markAsMostRecentChild()
    }
}
