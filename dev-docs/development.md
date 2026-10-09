# HyprSpace development

HyprSpace retains the `AeroSpace` Xcode target, `AeroSpaceApp` SwiftPM executable, `aerospace` CLI, and `bobko.aerospace` bundle identifier for compatibility. The app products are **HyprSpace.app** and **HyprSpace-Debug.app**.

## Requirements

Use full Xcode with a Swift 6.4 toolchain matching `.swift-version`. The app deployment target is macOS 13.0. The shell wrappers additionally require Bash 5 and swiftly; release documentation and completion generation use Ruby/Bundler, Rust, and fish. See `script/install-dep.sh` for pinned build dependencies.

## Build and test

With a matching Xcode toolchain, these commands avoid the wrappers' separate dependencies:

```sh
swift test
hyprspace_sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
swift build -Xlinker -platform_version -Xlinker macos -Xlinker 13.0 -Xlinker "$hyprspace_sdk_version"
.build/debug/AeroSpaceApp --config-path docs/config-examples/hyprspace-dwindle.toml
```

Quit the installed window manager before running a development instance. Grant Accessibility permission to the process hosting the app. The SDK flags enable the current macOS appearance while preserving the deployment target.

For an app bundle:

```sh
xcodebuild -project xcode/AeroSpace.xcodeproj -scheme AeroSpace -configuration Debug \
  -derivedDataPath .build/app CODE_SIGNING_ALLOWED=NO build
```

The app is `.build/app/Build/Products/Debug/HyprSpace-Debug.app`. Sign a bundle before distributing it; ad-hoc signing does not provide Developer ID trust or notarization.

The full repository checks use `./test.sh`, which builds, tests, formats, lints, and checks generated files. Run it from a clean checkout with the wrapper dependencies installed. `./generate.sh` regenerates Swift metadata and the Xcode project from `xcode/project.yml`.

## Defaults and compatibility

`docs/config-examples/default-config.toml` is the bundled HyprSpace default. The standalone dwindle example provides the same core layout and shortcuts. The refreshed v0.1.0 downloads include this default; earlier downloads must be replaced to get the updated app.

Personal configs remain at `~/.aerospace.toml` or `~/.config/aerospace/aerospace.toml`. Do not overwrite them during installation or upgrades.

## Releases

From a clean checkout with the build dependencies installed:

```sh
./build-release.sh --build-version 0.1.1 --codesign-identity -
```

This builds universal app and CLI binaries, embeds the version and commit hash, validates signatures, and creates ZIP/DMG downloads plus SHA-256 checksums in `.release`. The DMG includes an Applications shortcut. Temporary generated metadata is restored afterward; unrelated working files are never reset.

`./script/package-dmg.sh --build-version 0.1.1` repackages `.release/HyprSpace.app` after the matching ZIP has been created. `./install-from-sources.sh --dont-rebuild` installs a prepared build and CLI locally without Homebrew.

Tag creation and pushing are manual maintainer actions. Once the annotated release tag is on origin and points at HEAD, `./script/publish-release.sh --build-version 0.1.1` validates and builds the release, then creates a **draft** in `Li-RC/HyprSpace`. Review the assets before publishing. No script pushes Git refs automatically.

## Documentation and assets

`./build-docs.sh` generates the guide and manpages. `./build-shell-completion.sh` generates completion files for the retained `aerospace` command.

Edit `resources/AppIcon.icon` in Icon Composer. Export its default macOS rendition to `resources/Assets.xcassets/AppIcon.appiconset/icon.png` for compatibility, and update `docs/assets/icon.png` for the documentation. Both the Icon Composer document and fallback asset are compiled into app bundles.
