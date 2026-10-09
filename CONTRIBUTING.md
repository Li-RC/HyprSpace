# Contributing to HyprSpace

Use [HyprSpace issues](https://github.com/Li-RC/HyprSpace/issues) for bugs and feature requests, and pull requests for code or documentation changes. Search existing issues before opening a new one.

## Bug reports

Include the HyprSpace and macOS versions, reproduction steps, expected and actual behavior, and the relevant config. For window-management bugs, include `aerospace debug-windows` output or screenshots after removing private window titles and other sensitive information.

For shortcut problems, include the key combination, active binding mode, and output from `aerospace config --config-path`. HyprSpace keeps the `aerospace` CLI and config paths for compatibility.

## Changes

Keep patches focused, follow the surrounding Swift style, and explain the problem and resulting behavior in the PR description. Use Conventional Commits, such as `fix(groups): preserve focus when removing a member`.

Run the checks appropriate to the change. Swift changes should pass `swift test`; app-resource and bundle changes should also pass an Xcode app build. See [development.md](dev-docs/development.md) for build commands and the project's full validation scripts.

Do not rename compatibility identifiers or change existing personal configs as part of a branding-only patch. Changes to defaults should be documented and must not silently overwrite user configuration.

Contributions are licensed under the existing [MIT license](legal/LICENSE.txt). Preserve AeroSpace and third-party attribution and license notices.
