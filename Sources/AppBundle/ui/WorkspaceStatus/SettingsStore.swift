// Adapted from Workspace Status. See legal/workspace-status/LICENSE.
import Foundation
import Combine

enum MenuBarPosition: String, CaseIterable, Identifiable {
    case automatic, system
    var id: String { rawValue }
    var title: String { self == .automatic ? "Automatic" : "System position" }
}

@MainActor
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults
    var changed: (() -> Void)?
    @Published var menuBarPosition: MenuBarPosition {
        didSet {
            guard menuBarPosition != oldValue else { return }
            defaults.set(menuBarPosition.rawValue, forKey: "menuBarPosition")
            changed?()
        }
    }
    @Published var dockBadgesEnabled: Bool {
        didSet {
            guard dockBadgesEnabled != oldValue else { return }
            defaults.set(dockBadgesEnabled, forKey: "dockBadgesEnabled")
            changed?()
        }
    }
    @Published var compactViewEnabled: Bool {
        didSet {
            guard compactViewEnabled != oldValue else { return }
            defaults.set(compactViewEnabled, forKey: "compactViewEnabled")
            changed?()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        menuBarPosition = MenuBarPosition(rawValue: defaults.string(forKey: "menuBarPosition") ?? "") ?? .automatic
        dockBadgesEnabled = defaults.object(forKey: "dockBadgesEnabled") as? Bool ?? true
        compactViewEnabled = defaults.bool(forKey: "compactViewEnabled")
    }
}
