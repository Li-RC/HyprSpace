// Adapted from Workspace Status. See legal/workspace-status/LICENSE.
import AppKit
import ApplicationServices

struct DockBadge: Identifiable, Sendable {
    let name: String
    let bundle: String
    let value: String
    var id: String { bundle }
}

@MainActor
final class NotificationModel: ObservableObject {
    @Published var authorized = false
    @Published private(set) var monitoringEnabled = true
    @Published var badges: [DockBadge] = []
    @Published var monitorStatus = "Enable Accessibility to read Dock badges."
    var changed: (() -> Void)?
    private var timer: Timer?
    private let queue = DispatchQueue(label: "WorkspaceStatus.accessibility", qos: .utility)
    private var scanning = false
    private var generation = 0

    func start() {
        guard monitoringEnabled, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkPermission() }
        }
        checkPermission()
    }

    func setMonitoring(_ enabled: Bool) {
        guard monitoringEnabled != enabled else { return }
        monitoringEnabled = enabled
        if enabled { start() }
        else {
            stop()
            badges = []
            monitorStatus = "Dock badge monitoring is off."
            changed?()
        }
    }

    func enable() {
        let options = [axTrustedCheckOptionPrompt: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func checkPermission() {
        authorized = AXIsProcessTrusted()
        guard monitoringEnabled else { return }
        guard authorized else {
            monitorStatus = "Enable Accessibility to read Dock badges."
            badges = []
            changed?()
            return
        }
        monitorStatus = "Accessibility enabled · Dock badges only"
        scan()
    }

    private func scan() {
        guard monitoringEnabled, timer != nil, authorized, !scanning else { return }
        scanning = true
        let requestGeneration = generation
        let applications = NSWorkspace.shared.runningApplications
        var names: [String: String] = [:]
        for app in applications {
            if let name = app.localizedName, let bundle = app.bundleIdentifier,
               !["com.apple.notificationcenterui", "com.apple.UserNotificationCenter"].contains(bundle) {
                names[name] = bundle
            }
        }
        let dockPID = applications.first { $0.bundleIdentifier == "com.apple.dock" }?.processIdentifier
        let appNames = names
        queue.async {
            var badges: [DockBadge] = []
            if let dockPID {
                let root = AXUIElementCreateApplication(dockPID)
                AXUIElementSetMessagingTimeout(root, 0.25)
                var visited = 0
                Self.walk(root, depth: 0, visited: &visited) { element in
                    guard axValue(element, kAXSubroleAttribute) as? String == "AXApplicationDockItem",
                          let badge = axValue(element, "AXStatusLabel") as? String, !badge.isEmpty,
                          let name = axValue(element, kAXTitleAttribute) as? String,
                          let bundle = appNames[name] else { return }
                    badges.append(DockBadge(name: name, bundle: bundle, value: badge))
                }
            }
            let sortedBadges = badges.sorted { $0.name < $1.name }
            DispatchQueue.main.async {
                self.scanning = false
                guard self.monitoringEnabled, self.timer != nil, self.authorized else { return }
                guard requestGeneration == self.generation else { self.scan(); return }
                self.badges = sortedBadges
                self.changed?()
            }
        }
    }

    nonisolated private static func walk(_ element: AXUIElement, depth: Int, visited: inout Int, body: (AXUIElement) -> Void) {
        guard depth < 12, visited < 400 else { return }
        visited += 1
        body(element)
        for child in axChildren(element) { walk(child, depth: depth + 1, visited: &visited, body: body) }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        generation += 1
    }
}
