#!/bin/bash
#
# Guards the things CLAUDE.md warns drift silently between the package and the Xcode
# project, because both describe the same sources and nothing else notices when they disagree:
#
#   1. `SWIFT_VERSION` must stay 5.0, matching `.swiftLanguageMode(.v5)` in Package.swift.
#      Swift 6 language mode surfaces strict-concurrency errors throughout code never written
#      for it — so a stray bump breaks the Xcode build only, which `swift test` can't catch.
#   2. Dependency versions are declared twice. Bumped in one place only, the two build paths
#      compile against different code, and the tests keep passing while the app ships something
#      the suite never ran against.
#   3. `App/Info.plist` must not hardcode a version. It has to keep `$(MARKETING_VERSION)`, or the
#      literal wins over the version semantic-release passes to the build and the release ships an
#      app whose About window disagrees with the DMG's filename. Same class of silent drift as the
#      two above: nothing fails, the wrong number just ships.
#   4. `MACOSX_DEPLOYMENT_TARGET` in the Xcode project must match the floor in `.macOS(.vNN)` in
#      Package.swift. Diverging lets one build path silently accept API only the other's minimum
#      OS actually has — `swift test` runs against one floor while the shipped `.app` claims
#      another.
#
# Exits non-zero with an explanation rather than a diff, since the fix is always "make the other
# file agree" and which one is wrong depends on what you meant.

set -uo pipefail
cd "$(dirname "$0")/.."

status=0
fail() {
    echo "error: $1" >&2
    status=1
}

pbxproj="maillage.xcodeproj/project.pbxproj"
package="Package.swift"
pkg_resolved="Package.resolved"
xcode_resolved="maillage.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
info_plist="App/Info.plist"

for file in "$pbxproj" "$package" "$pkg_resolved" "$xcode_resolved" "$info_plist"; do
    [ -f "$file" ] || fail "missing $file"
done
[ "$status" -eq 0 ] || exit 1

# 1. Swift language version, every build configuration in the project.
bad_swift_version=$(grep -c 'SWIFT_VERSION = [^5]' "$pbxproj" || true)
if [ "$bad_swift_version" != "0" ]; then
    fail "$pbxproj sets SWIFT_VERSION to something other than 5.0 in $bad_swift_version place(s).
       Package.swift declares .swiftLanguageMode(.v5); Swift 6 mode breaks the Xcode build."
fi
if ! grep -q 'SWIFT_VERSION = 5.0;' "$pbxproj"; then
    fail "$pbxproj declares no SWIFT_VERSION = 5.0 at all."
fi
if ! grep -q 'swiftLanguageMode(.v5)' "$package"; then
    fail "$package no longer declares .swiftLanguageMode(.v5), which $pbxproj's
       SWIFT_VERSION = 5.0 mirrors. Change both together or neither."
fi

# 2. Dependency floors and the versions actually resolved.
#
# Compared as text via python rather than jq, which isn't on a stock macOS runner.
parity=$(
    python3 - "$package" "$pbxproj" "$pkg_resolved" "$xcode_resolved" <<'PY'
import json
import re
import sys

package, pbxproj, pkg_resolved, xcode_resolved = sys.argv[1:5]
problems = []

def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()

# Floors: `from: "5.1.0"` in Package.swift vs `minimumVersion = 5.1.0;` in the project.
package_floors = dict(
    (url.rsplit("/", 1)[-1].lower(), version)
    for url, version in re.findall(
        r'\.package\(\s*url:\s*"([^"]+)"\s*,\s*from:\s*"([^"]+)"', read(package)
    )
)
project_text = read(pbxproj)
project_floors = {}
for block in re.findall(
    r"repositoryURL = \"([^\"]+)\";\s*requirement = \{(.*?)\};", project_text, re.S
):
    url, requirement = block
    match = re.search(r"minimumVersion = ([0-9][^;]*);", requirement)
    if match:
        project_floors[url.rsplit("/", 1)[-1].lower()] = match.group(1).strip()

for name, floor in sorted(package_floors.items()):
    other = project_floors.get(name)
    if other is None:
        problems.append(f"{name}: declared in Package.swift ({floor}) but not in the Xcode project")
    elif other != floor:
        problems.append(
            f"{name}: Package.swift requires from {floor}, Xcode project requires from {other}"
        )
for name, floor in sorted(project_floors.items()):
    if name not in package_floors:
        problems.append(f"{name}: in the Xcode project ({floor}) but not in Package.swift")

# Resolved pins: the two Package.resolved files must agree exactly, or the two build paths
# compile against different code even with identical floors.
def pins(path):
    data = json.loads(read(path))
    return {
        pin.get("identity", "?"): pin.get("state", {}).get("version")
        or pin.get("state", {}).get("revision")
        for pin in data.get("pins", [])
    }

root_pins, xcode_pins = pins(pkg_resolved), pins(xcode_resolved)
for name in sorted(set(root_pins) | set(xcode_pins)):
    mine, theirs = root_pins.get(name), xcode_pins.get(name)
    if mine != theirs:
        problems.append(
            f"{name}: Package.resolved pins {mine}, the Xcode project's Package.resolved pins {theirs}"
        )

print("\n".join(problems))
PY
)

if [ -n "$parity" ]; then
    while IFS= read -r line; do
        [ -n "$line" ] && fail "$line"
    done <<<"$parity"
fi

# 3. The version has one source. Read with PlistBuddy rather than grepped, so the check is about
# the value the build actually sees and not about where the key sits in the file.
plist_version=$(
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist" 2>/dev/null || echo ""
)
plist_build=$(
    /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist" 2>/dev/null || echo ""
)
if [ "$plist_version" != '$(MARKETING_VERSION)' ]; then
    fail "$info_plist sets CFBundleShortVersionString to '$plist_version'.
       It must stay \$(MARKETING_VERSION): semantic-release passes the computed version to the
       build as MARKETING_VERSION, and a literal here overrides it silently."
fi
if [ "$plist_build" != '$(CURRENT_PROJECT_VERSION)' ]; then
    fail "$info_plist sets CFBundleVersion to '$plist_build'.
       It must stay \$(CURRENT_PROJECT_VERSION), for the same reason as the line above."
fi

# 4. Deployment target floor: `.macOS(.vNN)` in Package.swift vs every `MACOSX_DEPLOYMENT_TARGET`
# in the Xcode project. `.vNN` maps to `NN.0` (there is no minor-version form in this table yet).
package_floor=$(
    grep -oE '\.macOS\(\.v[0-9]+\)' "$package" | head -1 | grep -oE '[0-9]+'
)
if [ -z "$package_floor" ]; then
    fail "$package has no \`.macOS(.vNN)\` platform entry to compare against $pbxproj."
else
    pbxproj_targets=$(grep -oE 'MACOSX_DEPLOYMENT_TARGET = [0-9.]+;' "$pbxproj" | sort -u)
    mismatched=$(echo "$pbxproj_targets" | grep -vc "= ${package_floor}\.0;" || true)
    if [ "$mismatched" != "0" ]; then
        fail "$pbxproj's MACOSX_DEPLOYMENT_TARGET disagrees with $package's .macOS(.v${package_floor}):
$(echo "$pbxproj_targets" | sed 's/^/       /')
       Bump both together, or the two build paths run against different minimum OS versions."
    fi
fi

if [ "$status" -eq 0 ]; then
    echo "build parity: Package.swift and maillage.xcodeproj agree, and the version has one source"
fi
exit "$status"
