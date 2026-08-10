#!/bin/bash
#
# Builds Maillage.app in the Release configuration and leaves it in dist/, alongside a ditto
# archive of it. The one place the shippable app is compiled: CI's `package` stage and `make build`
# both call this, so the app you test locally is built by the same command that builds the one in
# the DMG.
#
# Two choices here are load-bearing:
#
#   1. Signing is left ON, unlike the old CI build's CODE_SIGNING_ALLOWED=NO. The project sets
#      CODE_SIGN_IDENTITY = "-" (ad-hoc), which needs no Developer ID and so works on a runner.
#      That matters because macOS on Apple silicon refuses to launch a *totally unsigned* app —
#      CODE_SIGNING_ALLOWED=NO answers "does it compile and link", not "does it run". A DMG built
#      from an unsigned app is a DMG nobody can open.
#
#   2. The archive is made with ditto, not zip. The app embeds MaillageCore.framework, which
#      carries symlinks (Versions/Current, and the top-level Resources/Headers) and a code
#      signature. zip flattens symlinks into copies, which breaks the bundle's structure and
#      invalidates the signature; ditto -c -k --keepParent is Apple's tool for exactly this and
#      preserves both. The archive exists so actions/upload-artifact can carry the .app between
#      CI stages without the same corruption — see the `package` job.
#
# Accepts an optional version to stamp: `build-app.sh 1.2.0` overrides MARKETING_VERSION for the
# build. With no argument the project's own MARKETING_VERSION is used, which is what you want
# locally. App/Info.plist reads $(MARKETING_VERSION), so this is the only lever needed.

set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:-}"

rm -rf dist
mkdir -p dist

build_args=(
    build
    -project maillage.xcodeproj
    -scheme Maillage
    -configuration Release
    -destination 'platform=macOS'
    -derivedDataPath build
)
if [ -n "$version" ]; then
    echo "==> Building Maillage.app at version $version"
    build_args+=("MARKETING_VERSION=$version")
else
    echo "==> Building Maillage.app at the project's own MARKETING_VERSION"
fi

# xcbeautify if it happens to be installed; raw xcodebuild otherwise, so this works on a bare
# runner and on a machine that has the nicety.
if command -v xcbeautify >/dev/null 2>&1; then
    set -o pipefail
    xcodebuild "${build_args[@]}" | xcbeautify
else
    xcodebuild "${build_args[@]}"
fi

app="build/Build/Products/Release/Maillage.app"
[ -d "$app" ] || {
    echo "error: xcodebuild reported success but $app does not exist." >&2
    exit 1
}

# The check that would have caught CODE_SIGNING_ALLOWED=NO shipping in a DMG. --deep so the
# embedded framework is verified too, since that is the part most likely to be broken by an
# archive round-trip.
echo "==> Verifying the signature"
codesign --verify --deep --strict --verbose=2 "$app"

cp -R "$app" dist/Maillage.app
ditto -c -k --keepParent dist/Maillage.app dist/Maillage.app.zip

echo "==> dist/Maillage.app"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/Maillage.app/Contents/Info.plist \
    | sed 's/^/    version: /'
