// Adapted from Workspace Status. See legal/workspace-status/LICENSE.
import AppKit
import SwiftUI

@MainActor
final class OverviewState: ObservableObject {
    @Published var expanded: Set<String> = []
}

struct GlassControl: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) { content.buttonStyle(.glass).buttonBorderShape(.capsule) }
        else { content.buttonStyle(.borderless) }
    }
}

struct WorkspaceSurface: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            content.background(Color.secondary.opacity(0.05),
                               in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct Overview: View {
    @ObservedObject var workspaces: WorkspaceModel
    @ObservedObject var notifications: NotificationModel
    @ObservedObject var placement: MenuPlacement
    let close: @MainActor () -> Void
    @ObservedObject var state: OverviewState
    let resized: (CGFloat) -> Void
    var openSettings: () -> Void = {}
    var width: CGFloat = 360
    var scale: CGFloat = 1
    var canvasHeight: CGFloat = 240

    func appRowHeight(in space: String) -> CGFloat {
        let columns = max(1, Int((width - 130) / 28))
        let rows = max(1, Int(ceil(Double(workspaces.snapshot.appBundles(in: space).count) / Double(columns))))
        return max(26, CGFloat(rows * 22 + (rows - 1) * 6))
    }

    var contentHeight: CGFloat {
        var workspaceElements: [CGFloat] = [34]
        if placement.notice != nil { workspaceElements.append(32) }
        if workspaces.error != nil { workspaceElements += [28, 14] }
        let spaces = workspaces.snapshot.occupiedSpaces
        if spaces.isEmpty { workspaceElements.append(34) }
        for space in spaces {
            let windowsHeight = state.expanded.contains(space) ? CGFloat(workspaces.snapshot.windows(in: space).count * 44) : 0
            workspaceElements.append(appRowHeight(in: space) + windowsHeight + 12)
            if space != spaces.last { workspaceElements.append(1) }
        }
        let workspaceHeight = workspaceElements.reduce(0, +) + CGFloat(workspaceElements.count - 1) * 8 + 24
        let noticesHeight: CGFloat = !notifications.monitoringEnabled ? 60 : notifications.authorized
            ? (notifications.badges.isEmpty ? 60 : 38 + CGFloat(notifications.badges.count * 32)) : 104
        return workspaceHeight + noticesHeight + 66
    }

    func select(_ space: String) {
        if space == workspaces.snapshot.current { close() }
        else { workspaces.perform(["workspace", space], completion: close) }
    }
    func focus(_ window: AppWindow) {
        workspaces.perform(["focus", "--window-id", String(window.id)], completion: close)
    }
    func openApp(_ bundle: String, in space: String? = nil, focusApp: Bool = false) {
        if let space {
            if let arguments = workspaces.navigationArguments(to: space, appBundle: bundle, focusApp: focusApp) {
                workspaces.perform(arguments, completion: close)
            } else { close() }
            return
        }
        if let window = workspaces.snapshot.windows.first(where: {
            $0.bundle == bundle
        }) {
            focus(window)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
            close()
        }
    }

    @ViewBuilder var sections: some View {
        VStack(spacing: 10) {
            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Workspace Status").font(.headline)
                            Text("Workspace \(workspaces.snapshot.current)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(action: openSettings) { Image(systemName: "gearshape") }
                            .buttonStyle(.borderless).help("Settings…")
                            .accessibilityLabel("Settings").accessibilityIdentifier("openSettings")
                        Button { workspaces.refresh() } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless).help("Refresh workspaces")
                    }.frame(height: 34)
                    if let notice = placement.notice {
                        Text(notice).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(height: 32)
                    }
                    if let error = workspaces.error {
                        Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).lineLimit(2).frame(height: 28)
                        Text("Check HyprSpace, then refresh.").font(.caption).foregroundStyle(.secondary).frame(height: 14)
                    }
                    if workspaces.snapshot.occupiedSpaces.isEmpty {
                        Text("No workspaces with open windows.").font(.caption).foregroundStyle(.secondary).frame(height: 34)
                    }
                    ForEach(workspaces.snapshot.occupiedSpaces, id: \.self) { space in
                        let windows = workspaces.snapshot.windows(in: space)
                        let bundles = workspaces.snapshot.appBundles(in: space)
                        let current = space == workspaces.snapshot.current
                        VStack(spacing: 6) {
                            HStack(spacing: 8) {
                                Button { select(space) } label: {
                                    Text(space).font(.system(.body, design: .rounded).weight(.bold))
                                        .frame(minWidth: 26, minHeight: 26)
                                        .background(current ? Color.accentColor : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                        .foregroundStyle(current ? Color.white : Color.primary)
                                }.buttonStyle(.plain).help("Switch to workspace \(space)")
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 22, maximum: 22))], alignment: .leading, spacing: 6) {
                                    ForEach(bundles, id: \.self) { bundle in
                                        WorkspaceAppButton(bundle: bundle, name: windows.first { $0.bundle == bundle }?.app ?? bundle,
                                            current: current, space: space,
                                            singleClick: { openApp(bundle, in: space) },
                                            doubleClick: { openApp(bundle, in: space, focusApp: true) })
                                            .frame(width: 20, height: 20)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Button {
                                    withAnimation(.easeOut(duration: 0.12)) {
                                        if state.expanded.contains(space) { state.expanded.remove(space) } else { state.expanded.insert(space) }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text("\(windows.count)").monospacedDigit()
                                        Image(systemName: state.expanded.contains(space) ? "chevron.up" : "chevron.down")
                                    }.font(.caption).foregroundStyle(.secondary)
                                }.buttonStyle(.borderless).help("Show windows in workspace \(space)")
                            }
                            if state.expanded.contains(space) {
                                ForEach(windows) { window in
                                    Button { focus(window) } label: {
                                        HStack(spacing: 8) {
                                            AppIcon(bundle: window.bundle)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(window.app).font(.caption.weight(.medium)).lineLimit(1)
                                                Text(window.title.isEmpty ? "Untitled window" : window.title)
                                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                            Spacer()
                                            Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                                        }.padding(5).frame(height: 38).contentShape(Rectangle())
                                    }.buttonStyle(.plain).help("Focus \(window.title)")
                                }
                            }
                        }.padding(.vertical, 6).frame(maxWidth: .infinity)
                        if space != workspaces.snapshot.occupiedSpaces.last { Divider() }
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(WorkspaceSurface())
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notifications").font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(height: 14)
                    if !notifications.monitoringEnabled {
                        Text("Dock badge monitoring is off.").font(.caption).foregroundStyle(.secondary).frame(height: 14)
                    } else if !notifications.authorized {
                        Text("Allow Accessibility to read app badges in the Dock.").font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(height: 28)
                        Button("Enable Accessibility…") { notifications.enable() }.modifier(GlassControl()).controlSize(.small).frame(height: 22)
                    } else if notifications.badges.isEmpty {
                        Text("No notifications to show.").font(.caption).foregroundStyle(.secondary).frame(height: 14)
                    } else {
                        ForEach(notifications.badges) { badge in
                            Button { openApp(badge.bundle) } label: {
                                HStack {
                                    AppIcon(bundle: badge.bundle)
                                    Text(badge.name).font(.callout).lineLimit(1)
                                    Spacer()
                                    Text(badge.value).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                                }.frame(height: 24).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(WorkspaceSurface())
            }.padding(2)
            Button("Quit HyprSpace") { WorkspaceStatusController.shared.quit(nil) }
                .modifier(GlassControl()).controlSize(.small).font(.caption).frame(height: 22)
        }.padding(10)
    }

    var body: some View {
        Group {
            if #available(macOS 26.0, *) { GlassEffectContainer(spacing: 4) { sections } }
            else { sections }
        }.frame(width: width, height: contentHeight, alignment: .top)
            .onAppear { resized(contentHeight) }
            .onChange(of: contentHeight) { height in
                DispatchQueue.main.async { resized(height) }
            }
            .modifier(NoFocusOutline())
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: width * scale, height: canvasHeight * scale, alignment: .topLeading)
    }

}
