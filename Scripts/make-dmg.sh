#!/bin/bash
#
# Wraps a built Maillage.app into dist/Maillage-<version>.dmg — the artifact attached to every
# GitHub release. Called by semantic-release's `prepareCmd` (see .releaserc.json), which runs
# before `publish`, so the file exists by the time the release's assets are uploaded.
#
# hdiutil rather than a packaging dependency: it ships with macOS, so there is no version to pin
# and nothing that can change the output from under the repo — the same reason Xcode and SwiftLint
# are pinned rather than tracked. The layout is the conventional one, an app beside an
# /Applications symlink, so the window explains the install without instructions.
#
# UDZO is zlib-compressed and read-only. Read-only matters: a writable image would let someone
# modify the app in place, which breaks the ad-hoc signature and makes the app refuse to launch
# with no hint as to why.

set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <path-to-Maillage.app> <version>" >&2
    exit 1
fi

app="$1"
version="$2"

[ -d "$app" ] || {
    echo "error: $app does not exist. Run Scripts/build-app.sh first." >&2
    exit 1
}

# The app in the DMG must claim the version in its filename, or the About window and the download
# disagree and there is no way to tell which is right. App/Info.plist reads $(MARKETING_VERSION),
# so this is really checking that build-app.sh was passed the same version we were.
built_version=$(
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
        "$app/Contents/Info.plist" 2>/dev/null || echo "?"
)
if [ "$built_version" != "$version" ]; then
    echo "error: $app reports version $built_version but the DMG would be named $version." >&2
    echo "       Rebuild with: Scripts/build-app.sh $version" >&2
    exit 1
fi

mkdir -p dist
dmg="dist/Maillage-$version.dmg"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

# ditto, not cp -R: preserves the symlinks and signature inside MaillageCore.framework. See the
# header of build-app.sh for what a plain copy costs.
ditto "$app" "$stage/Maillage.app"
ln -s /Applications "$stage/Applications"

echo "==> Building $dmg"
hdiutil create \
    -volname "Maillage $version" \
    -srcfolder "$stage" \
    -ov \
    -format UDZO \
    -quiet \
    "$dmg"

# Proves the image mounts and that the app survived compression signed — a corrupt DMG otherwise
# only reveals itself to whoever downloads it.
echo "==> Verifying $dmg"
hdiutil verify -quiet "$dmg"
mount_point=$(mktemp -d)
hdiutil attach "$dmg" -readonly -nobrowse -quiet -mountpoint "$mount_point"
trap 'hdiutil detach "$mount_point" -quiet 2>/dev/null || true; rm -rf "$stage" "$mount_point"' EXIT
codesign --verify --deep --strict "$mount_point/Maillage.app"
hdiutil detach "$mount_point" -quiet

echo "==> $dmg ($(du -h "$dmg" | cut -f1))"
