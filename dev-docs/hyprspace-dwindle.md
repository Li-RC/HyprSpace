# HyprSpace: dwindle, window groups, and borders

HyprSpace adds opt-in binary tiling, window groups with a member bar, and
configurable focused and inactive window borders. Animations are deferred.
Executable names and the config search paths still use AeroSpace's names.

Set `enable-dwindle-tiling = true` at the top level of your configuration,
before any `[table]` headers, or use the supplied standalone sample config.
It defaults to false.

## Behavior

- Opening or retiling a window splits the most recently focused tiled window.
  A focused floating window does not replace this tiled insertion target.
- The split is horizontal when the target tile is wider than it is tall,
  otherwise vertical. Both new children start with equal weight.
- Tile sizes are calculated from the current tree, even when newly detected
  windows have not been laid out yet.
- Split orientations stay fixed after creation, like Hyprland with
  `preserve_split` enabled. Automatic alternating-orientation normalization
  is bypassed while dwindle is enabled.
- Closing a window collapses the redundant split even if ordinary flattening
  is disabled. Commands that leave more than two tiled siblings are normalized
  into a binary tree, preserving window order and the recent focus target.
- Moving a tiled window to another workspace splits that workspace's most
  recently focused tiled window. Explicit insertion indices retain their
  existing behavior and are subsequently normalized.
- Existing focus, move, resize, fullscreen, floating, and workspace commands
  remain available. Accordion containers retain their accordion layout.
- Disabling dwindle stops binary normalization and split insertion; it does
  not undo the existing tree. `flatten-workspace-tree` can flatten it afterward.

## Groups and borders

`group toggle` marks the focused tiled window as a group. New tiled windows join
that group while it is the tiled insertion target. Only the active member is
shown; other members use AeroSpace's existing offscreen hiding mechanism.
The bar shows application names on a native Liquid Glass background on macOS 26 and later (material on older macOS),
with an 8-point gap above the window. Click a tab to switch to that member, or
cycle members with the keyboard. Drag a tab across another tab and release to
reorder the members; an insertion marker shows the destination. The active window
stays selected, and releasing outside the bar cancels the reorder.

`group next` and `group prev` wrap through members. `group join-right` (or another
direction) joins a neighbor; if both tiles are groups, it merges their members.
`group remove` extracts the active member. `group toggle` on an existing group
also extracts only the target window, leaving the other members grouped. Closing
the active member selects a remaining one.
Directional focus treats a group as one tile, and resizing adjusts its whole tile.
The active member and group structure are included in the restoration cache.

Directional movement moves the whole group and swaps with adjacent tiles without
changing membership. In dwindle mode, movement stops at the workspace edge by
default; an explicit `--boundaries-action` overrides this.
Workspace and monitor transfer, floating, and dragging operate on the individual
member. In nested splits, movement stops beside the group. Use the explicit
`group join-*` commands or dragging to change membership.
In dwindle mode, drag a window by its title bar and release near another tile's
left/right edge to create a horizontal split, or top/bottom edge for a vertical
split. A faint overlay previews the resulting tile while dragging. The outer
quarter on each side selects left/right; the central area selects top/bottom.
The narrow border gap also accepts drops. The tree changes on release, so crossing
tiles does not keep swapping them.
Dropping a tiled or floating window in a group's center or on its bar joins it;
dropping near its edges creates a separate tile beside the group. Dragging a member
to its own group's edge extracts that member.
`flatten-workspace-tree` dissolves groups in the target workspace.

Borders are disabled by default. To enable them, add this table to your config:

```toml
[window-borders]
enabled = true
width = 2
active-color = '#89b4fa'
inactive-color = '#45475a'
```

Width accepts integers from 1 to 8 points, and colors use `#RRGGBB`.
Borders follow the 16-point standard window corner radius measured through
AppKit on macOS 27, with the stroke radius adjusted for border thickness.
The supplied sample enables borders for tiled and floating windows. Borders and
bars update with the window manager's existing refresh events. They use
nonactivating panels ordered above their corresponding windows. Borders are
click-through; only the narrow group bar receives clicks. Decorations
are removed for inactive group members, invisible workspaces, fullscreen,
disabled window management, and shutdown. Reloading the config updates their style.

## Build and run manually

The checked-out package requires Swift 6.2 or newer; its development toolchain
is Swift 6.4. The Xcode toolchain installed on this machine can build it directly.
These commands avoid the shell wrappers' separate Bash 5 and swiftly requirements:

```sh
cd /Users/liruochong/Documents/HyprSpace
swift test
swift build
```

Quit your currently running AeroSpace before starting this build so that two
window managers do not manage the same windows. Then run in Terminal:

```sh
.build/debug/AeroSpaceApp --config-path docs/config-examples/hyprspace-dwindle.toml
```

If macOS requests Accessibility access, grant it to the Terminal app hosting
the debug executable, then relaunch the command. This is an unsigned development
build, not an installed HyprSpace app bundle. The server and CLI still use the
upstream names and debug socket.

Debug startup explicitly selects the accessory application policy. Without it,
the bare SwiftPM executable starts with the prohibited policy and can register
shortcuts while missing their keyboard events.

The sample config has no startup commands and does not enable login startup.
It uses Control for these shortcuts:

| Action | Shortcut |
| --- | --- |
| Focus left/down/up/right | Control + H/J/K/L |
| Move left/down/up/right | Control + Shift + H/J/K/L |
| Shrink/grow current split | Control + minus/equal |
| Toggle fullscreen | Control + F |
| Toggle floating/tiling | Control + Shift + F |
| Switch workspace | Control + 1/2 |
| Send window to workspace | Control + Shift + 1/2 |
| Reload this config | Control + Shift + R |
| Create group / extract current member | Control + G |
| Next/previous group member | Control + Tab / Control + Shift + Tab |
| Extract member from group | Control + Shift + G |
| Join neighbor in direction | Control + Shift + arrow key |

## Manual checks

1. On a landscape screen, open two ordinary windows. Expect a side-by-side split.
2. Focus the right tile and open a third window. If that tile is taller than it
   is wide, expect it to split top/bottom while the left tile keeps its space.
   On very wide screens, a half-screen tile may still be wider than it is tall,
   so another side-by-side split is expected.
3. Focus the left tile and open another window. Expect only that tile to split.
4. Close one member of a split. Expect the other to reclaim its tile.
5. Try directional focus and movement, then shrink/grow a split.
6. Toggle a window floating and back. Expect it to rejoin by splitting a tile.
7. Open windows on workspace 2, then send a window there from workspace 1.
   Expect insertion beside the destination's most recent tiled window.
8. If you use a second monitor, repeat insertion, movement, and workspace switching there.

9. Press Control + G on a tile, then open two windows. Expect a group bar and
   only the last member shown. Click each tab, then cycle with Control + Tab and
   Control + Shift + Tab. Check that clicking a tab immediately focuses its member
   and that clicks inside the application still reach it.
10. Close the active member. Expect a remaining member to occupy the tile without
    needing a click. Extract a member with Control + Shift + G, then join the
    neighbor with Control + Shift + an arrow key. Press Control + G to extract only the current member; the other members stay grouped.
11. Check that the blue border follows focus, inactive borders are muted, and
    decorations disappear on hidden workspaces and fullscreen. Toggle floating
    and check its border. Reload after changing border width or colors.

Report the failing step, affected application, expected result, and observed
result. A screenshot is optional. For a text list of managed windows use:

```sh
.build/debug/aerospace list-windows --all
```

If shortcuts still do not work, run these commands while the debug server is running:

```sh
.build/debug/aerospace config --config-path
.build/debug/aerospace config --get mode.main.binding --keys
.build/debug/aerospace trigger-binding --mode main ctrl-2
```

The last command should switch to workspace 2 without a physical keypress. If
it works while Control + 2 does not, the remaining problem is keyboard
event delivery or shortcut registration rather than the workspace command.
Send the output and whether the workspace switched. This sample uses Control as its base modifier.

To end the trial, quit the development server from its tray menu (or stop its
Terminal process) and restart your usual AeroSpace. Your normal config is not
changed by this trial. GUI and real-window behavior require these manual checks;
unit tests alone do not verify application size limits or macOS Accessibility behavior.
