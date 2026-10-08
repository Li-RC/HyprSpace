import AppKit
import Common

@MainActor
final class WorkspaceModel: ObservableObject {
    static let shared = WorkspaceModel()
    @Published var snapshot = Snapshot(spaces: [], current: "?", windows: [])
    @Published var error: String?
    var changed: (() -> Void)?
    private var recentWindowIDs: [Int] = []
    private var titles: [UInt32: String] = [:]
    private var titleTask: Task<Void, Never>?

    func updateFromTree() {
        let spaces = Workspace.all
        let windows = spaces.flatMap { workspace in
            workspace.allLeafWindowsRecursive.compactMap { window -> AppWindow? in
                guard window.app.pid != myPid else { return nil }
                let item = AppWindow(id: Int(window.windowId), app: window.app.name ?? "Application",
                                     bundle: window.app.rawAppBundleId ?? "", title: titles[window.windowId] ?? "",
                                     workspace: workspace.name)
                return item.isWorkspaceApplication ? item : nil
            }
        }
        if let id = focus.windowOrNil.map({ Int($0.windowId) }) {
            recentWindowIDs.removeAll { $0 == id }
            recentWindowIDs.insert(id, at: 0)
        }
        recentWindowIDs.removeAll { id in !windows.contains { $0.id == id } }
        let ids = Set(windows.map { UInt32($0.id) })
        titles = titles.filter { ids.contains($0.key) }
        let next = Snapshot(spaces: spaces.map(\.name), current: focus.workspace.name, windows: windows)
        if next != snapshot { snapshot = next; changed?() }
    }

    func navigationArguments(to space: String, appBundle: String? = nil, focusApp: Bool = false) -> [String]? {
        if space != snapshot.current && !focusApp { return ["workspace", space] }
        guard let bundle = appBundle else { return nil }
        let windows = snapshot.windows(in: space).filter { $0.bundle == bundle }
        let window = recentWindowIDs.compactMap { id in windows.first { $0.id == id } }.first ?? windows.first
        return window.map { ["focus", "--window-id", String($0.id)] }
    }

    // Titles are queried only when the overview is opened or explicitly refreshed.
    // Workspace/app changes themselves come directly from HyprSpace's refresh events.
    func refresh() {
        updateFromTree()
        titleTask?.cancel()
        let ids = snapshot.windows.map { UInt32($0.id) }
        titleTask = Task { @MainActor in
            for id in ids {
                guard !Task.isCancelled else { return }
                guard let window = Window.get(byId: id) else { continue }
                if let title = try? await window.getTitle(.cancellable), !Task.isCancelled { titles[id] = title }
            }
            if !Task.isCancelled { updateFromTree() }
        }
    }

    func perform(_ arguments: [String], completion: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            do {
                let command = parseCommand(arguments)
                guard let command = command.cmdOrNil else { error = "Invalid workspace action."; changed?(); return }
                if !TrayMenuModel.shared.isEnabled && !["enable", "reload-config"].contains(arguments.first ?? "") {
                    error = "Enable HyprSpace to switch workspaces."; changed?(); return
                }
                let result = try await runLightSession(.menuBarButton, .forceRun) {
                    await command.run(.defaultEnv, CmdIoImpl.emptyStdinIgnoringOut)
                }
                guard result.rawValue == 0 else { error = "HyprSpace could not complete that action."; changed?(); return }
                error = nil
                updateFromTree()
                changed?()
                completion()
            } catch { self.error = error.localizedDescription; changed?() }
        }
    }

    func stop() { titleTask?.cancel(); titleTask = nil }
}

@MainActor
public final class WorkspaceStatusAppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        WorkspaceStatusController.shared.start()
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        WorkspaceStatusController.shared.showSettings(nil)
        return false
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    public func applicationWillTerminate(_ notification: Notification) {
        WorkspaceStatusController.shared.stop()
    }
}
