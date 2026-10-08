import Common

struct GroupCommand: Command {
    let args: GroupCmdArgs
    let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io), let window = target.windowOrNil else {
            return .fail(io.err(noWindowIsFocused))
        }
        guard window.parent is TilingContainer else { return .fail(io.err("Groups require a tiled window")) }
        switch args.action.val {
            case .toggle:
                if let group = window.windowGroup { group.isWindowGroup = false } else { window.createWindowGroup() }
            case .remove:
                guard window.windowGroup != nil else { return .fail(io.err("Window is not grouped")) }
                window.removeFromWindowGroup()
            case .next, .prev:
                guard let group = window.windowGroup, let index = window.ownIndex else { return .fail(io.err("Window is not grouped")) }
                let delta = args.action.val == .next ? 1 : -1
                let member = group.children[(index + delta + group.children.count) % group.children.count] as! Window
                return member.focusWindow() ? .succ : .fail
            case .joinLeft, .joinDown, .joinUp, .joinRight:
                let direction: CardinalDirection = switch args.action.val {
                    case .joinLeft: .left
                    case .joinDown: .down
                    case .joinUp: .up
                    default: .right
                }
                guard let (parent, index) = window.closestParent(hasChildrenInDirection: direction, withLayout: nil),
                      let neighbor = parent.children[index + direction.focusOffset].findLeafWindowRecursive(snappedTo: direction.opposite)
                else { return .fail(io.err("No tiled neighbor in that direction")) }
                let members = window.windowGroup?.allLeafWindowsRecursive ?? [window]
                let group = neighbor.createWindowGroup()
                for member in members { member.bind(to: group, adaptiveWeight: 1, index: INDEX_BIND_LAST) }
        }
        window.markAsMostRecentChild()
        return .succ
    }
}
