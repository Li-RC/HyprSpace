# Integrated workspace status

HyprSpace includes Workspace Status in its own process, replacing the original AeroSpace menu bar item. Workspace changes update directly from HyprSpace's tree and focus events; workspace switching does not invoke the CLI or poll a separate server.

## Try it

Quit the standalone Workspace Status app and any running HyprSpace/AeroSpace instance, then run from the HyprSpace repository:

```sh
hyprspace_sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
swift build -Xlinker -platform_version -Xlinker macos -Xlinker 13.0 -Xlinker "$hyprspace_sdk_version"
.build/debug/AeroSpaceApp --config-path docs/config-examples/hyprspace-dwindle.toml
```

The SDK linker flags enable the current macOS system appearance while keeping macOS 13 as the deployment target. A plain `swift build` can record SDK 13 in the executable metadata; `build-debug.sh` also supplies the correct SDK version automatically.

The executable name remains `AeroSpaceApp`. Accessibility permission belongs to the process running HyprSpace; the standalone Workspace Status app's permission does not transfer.

## Controls

- Click an inactive workspace to switch to it, preserving its focused window.
- Click an app in the current workspace to focus its most recently focused window.
- Double-click an app to switch to its workspace and focus it.
- Click the bell for the workspace overview and Dock unread badges. Expand a workspace to select an individual window, including a hidden group member.
- Right-click anywhere on the strip for Settings, Enable/Disable HyprSpace, Reload config, Open config, and Quit HyprSpace.

Settings include compact workspace indicators, Dock badge monitoring, and automatic/system placement. Automatic placement centers the workspace strip on displays without a notch when there is room; displays with a notch keep the native position. System placement uses the normal macOS status item and supports Command-drag. When automatic placement cannot read menu positions, it falls back to the native item.

Menu appearance settings are saved with HyprSpace. Start at login remains controlled by `start-at-login` in the HyprSpace config. Dock badge monitoring reads unread indicators from the Dock, not Notification Center or notification contents.

The reused Workspace Status components retain their [MIT license](../legal/workspace-status/LICENSE).
