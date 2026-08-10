#!/bin/bash
#
# Prints the install section appended to every GitHub release body, below the generated changelog.
# Wired in as semantic-release's `generateNotesCmd`: notes from several plugins are concatenated in
# plugin order, so this is simply the last contributor rather than an edit made after publishing.
#
# It exists because the DMG is ad-hoc signed and cannot be notarized — this machine has no
# Developer ID, the same reason the project sets CODE_SIGN_IDENTITY = "-". macOS therefore
# quarantines the app on download and reports it as damaged or unopenable, which looks like a
# broken build rather than a missing $99/year membership. The way past it belongs *in* the release,
# next to the download, not in a document someone has to already know to look for.
#
# stdout is the release body, so print nothing else here.

set -euo pipefail

cat <<'EOF'

---

## Installing

Download the `.dmg` below, open it, and drag **Maillage** to your Applications folder.

Maillage is ad-hoc signed and **not notarized**, so macOS quarantines it on first open and will say
it "cannot be opened because Apple cannot check it for malicious software". That is expected — the
app is not signed with a paid Developer ID. To open it anyway:

1. Right-click (or Control-click) **Maillage** in Applications and choose **Open**
2. Click **Open** again in the dialog

macOS remembers the choice, so this is a one-time step. If the dialog offers no Open button, clear
the quarantine flag directly:

```sh
xattr -dr com.apple.quarantine /Applications/Maillage.app
```

Requires macOS 14 (Sonoma) or later. Universal — Apple silicon and Intel.
EOF
