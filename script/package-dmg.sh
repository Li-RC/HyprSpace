#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

build_version=""
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        *) echo "Unknown option: $1" >&2; exit 1;;
    esac
done
if test -z "$build_version"; then
    echo "--build-version is required" >&2
    exit 1
fi

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ditto .release/HyprSpace.app "$stage/HyprSpace.app"
ln -s /Applications "$stage/Applications"
dmg=".release/HyprSpace-v$build_version.dmg"
hdiutil create -ov -volname "HyprSpace $build_version" -srcfolder "$stage" -fs HFS+ -format UDZO "$dmg"
hdiutil verify "$dmg"
(cd .release && shasum -a 256 "HyprSpace-v$build_version.dmg" > "HyprSpace-v$build_version.dmg.sha256")
