#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

rebuild=1
while test $# -gt 0; do
    case $1 in
        --dont-rebuild) rebuild=0; shift;;
        *) echo "Unknown option: $1" >&2; exit 1;;
    esac
done
if pgrep -f '^/Applications/HyprSpace.app/Contents/MacOS/' >/dev/null; then
    echo "Quit HyprSpace before installing a new build." >&2
    exit 1
fi
if test "$rebuild" = 1; then
    ./build-release.sh --codesign-identity -
fi
ditto .release/HyprSpace.app /Applications/HyprSpace.app
mkdir -p "$HOME/.local/bin"
cp .release/aerospace "$HOME/.local/bin/aerospace"
echo "Installed HyprSpace.app and ~/.local/bin/aerospace. Add ~/.local/bin to PATH if needed."
