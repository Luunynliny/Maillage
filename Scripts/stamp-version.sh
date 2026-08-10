#!/bin/bash
#
# Rewrites a built Maillage.app's version in place and re-signs it. Runs in CI's `release` stage,
# via semantic-release's `prepareCmd`, on the bundle the `package` stage built.
#
# Why stamp rather than rebuild: the version only exists once semantic-release has analyzed the
# commits, which is after the build. Rebuilding there would cost another few minutes and — the real
# objection — would produce a *different* binary from the one the pipeline just tested and signed.
# Only Info.plist differs between "the app we tested" and "the app we ship", so only Info.plist is
# touched.
#
# Editing anything inside a bundle invalidates its signature, so the re-sign is not optional: an
# app with a broken signature is worse than an unsigned one, because macOS reports it as damaged.
# Ad-hoc (`-`) matches what the project itself uses, and needs no Developer ID.
#
# Locally there is nothing to stamp — `Scripts/build-app.sh <version>` bakes the version in at
# build time — so this script only exists for the build-once-ship-once path.

set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <path-to-Maillage.app> <version>" >&2
    exit 1
fi

app="$1"
version="$2"
plist="$app/Contents/Info.plist"

[ -f "$plist" ] || {
    echo "error: $plist does not exist — $app is not an app bundle." >&2
    exit 1
}

echo "==> Stamping $app as $version"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"

# Re-sign the framework before the app: signing is inside-out, and signing the outer bundle first
# would seal a signature that the inner one then contradicts.
for framework in "$app/Contents/Frameworks/"*.framework; do
    [ -d "$framework" ] || continue
    codesign --force --sign - --timestamp=none "$framework"
done
codesign --force --sign - --timestamp=none "$app"

codesign --verify --deep --strict --verbose=2 "$app"
echo "==> $app is now $version, ad-hoc signed"
