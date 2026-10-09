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

# Tag creation and pushing are explicit maintainer actions, never performed here.
tag="v$build_version"
test "$(git rev-parse "$tag^{}")" = "$(git rev-parse HEAD)"
remote_commit=$(git ls-remote origin "refs/tags/$tag^{}" | awk '{print $1}')
test "$remote_commit" = "$(git rev-parse HEAD)" || {
    echo "Push the annotated $tag tag to origin before publishing." >&2
    exit 1
}
./test.sh
./build-release.sh --build-version "$build_version" --codesign-identity -

notes=$(mktemp)
trap 'rm -f "$notes"' EXIT
cat > "$notes" <<EOF
HyprSpace $tag: macOS tiling with dwindle layouts, window groups, and integrated workspace status.

Open the DMG and drag HyprSpace to Applications. The ZIP includes the CLI, manpages, shell completions, and license notices. SHA-256 checksums accompany both downloads.

Universal Apple Silicon and Intel binaries; macOS 13.0 deployment target. Ad-hoc signed and not notarized.
EOF
gh release create "$tag" --repo Li-RC/HyprSpace --verify-tag --draft \
    --title "HyprSpace $tag" --notes-file "$notes" \
    ".release/HyprSpace-v$build_version.dmg" \
    ".release/HyprSpace-v$build_version.dmg.sha256" \
    ".release/HyprSpace-v$build_version.zip" \
    ".release/HyprSpace-v$build_version.zip.sha256"
echo "Draft created. Verify the assets before publishing it on GitHub."
