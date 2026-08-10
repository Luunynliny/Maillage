# maillage

A personal CRM with Obsidian's look and feel. People, organizations and projects live as
markdown files with YAML frontmatter; labeled one-way relations between people are visualized
as a force-directed graph clustered by employer.

## Stack

| Piece | Choice |
|---|---|
| Language | Swift 6 (`.swiftLanguageMode(.v5)`), SwiftUI, macOS 14+ |
| Build | Two paths — SwiftPM for tests, `maillage.xcodeproj` for running (see Building) |
| State | `@Observable` + `@MainActor` `VaultStore`, injected via `.environment(store)` |
| Tests | Swift Testing (`@Test`, `@Suite`, `#expect`, `#require`) — **not** XCTest |
| YAML | [Yams](https://github.com/jpsim/Yams) (MIT) |

Swift is a hard requirement: a later phase captures macOS system audio via Core Audio process
taps, which has no cross-platform equivalent.

**Open source first.** Every dependency added must be OSS with a permissive license, noted in
the table above with its license.

## Building

Two build systems describe the same sources, deliberately. Pick by what you're doing:

| Task | Use | Why |
|---|---|---|
| Tests, quick compile check | `rtk swift test` | ~0.2s. Xcode's runner takes ~80s for the same 91 tests |
| Running, debugging, breakpoints | `open maillage.xcodeproj` → scheme **Maillage** → ⌘R | Only path that produces a real `.app` |

`maillage.xcodeproj` has two targets mirroring the package: `MaillageCore.framework` and
`Maillage.app`, which embeds it. Both use **buildable folders** (`PBXFileSystemSynchronizedRootGroup`)
pointed at `Sources/`, so a new `.swift` file joins its target with no project edit.

Watch out for:

- **`SWIFT_VERSION` must stay `5.0`** in the project, matching `.swiftLanguageMode(.v5)` in
  `Package.swift`. Swift 6 language mode surfaces strict-concurrency errors throughout code that
  was never written for it.
- **Dependency versions are declared twice** — `Package.swift` and `project.pbxproj`. Bump both
  together or the two build paths compile against different code.
- **Pick the `Maillage` scheme, not the lowercase `maillage` one.** The latter is SwiftPM's, and
  it produces a bare executable with no `Info.plist` — so AppKit leaves the activation policy at
  `.prohibited`, the app never becomes active, and an inactive app owns neither the cursor nor the
  key window: no control shows a hand and no text field takes focus. `MaillageApp` now forces
  `.regular` at init so that build is usable too, but the bundled scheme is still the one to run.
- Signing is manual and ad-hoc (`CODE_SIGN_IDENTITY = "-"`), because this machine has no
  Developer ID. The App Sandbox is **off**, so the vault stays a plain readable folder; there is
  no entitlements file yet. The audio phase will need one (`App/Maillage.entitlements`, referenced
  by `CODE_SIGN_ENTITLEMENTS`) alongside the `NSAudioCaptureUsageDescription` already in
  `App/Info.plist`.

Both tools need Xcode's toolchain rather than Command Line Tools. `xcode-select` is already
pointed at Xcode; if a fresh machine errors out, run
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

## CI

`.github/workflows/ci.yml` runs on every push and PR to `main` and `develop`, in three parallel
jobs. `make check` runs the same things locally, in the same order — reproduce a red check with
one command rather than reading the workflow.

| Job | Runs | Guards |
|---|---|---|
| Format & lint | `swift format lint`, SwiftLint, `Scripts/check-build-parity.sh` | Needs no build, so it reports in under a minute |
| Tests | `swift test` | The 91 tests, via the fast path |
| Build app bundle | `xcodebuild -scheme Maillage` with signing off | That the project file, `Info.plist` and embedded framework still produce a real `.app` — breakage `swift test` passes straight through |

| Target | What it does |
|---|---|
| `make check` | Everything CI runs |
| `make format` | Rewrites sources to match `.swift-format` (CI only *checks*) |
| `make lint` | SwiftLint — needs `brew install swiftlint` |
| `make parity` | Just the two-build-system check |

Both quality tools are **pinned**: the runner uses Xcode 16.4 (so `swift format`'s rules can't
change under the repo) on `macos-15`, and SwiftLint by release version. `macos-14` cannot be used
— it is deprecated and tops out at Xcode 15.4, which is Swift 5.10, and `Package.swift` declares
`swift-tools-version: 6.0`.

Watch out for:

- **`swift format` owns layout; SwiftLint owns semantics, and the split is load-bearing.** The two
  genuinely disagree — `swift format` adds trailing commas to multiline literals that SwiftLint's
  `trailing_comma` removes, and puts a lone `{` on its own line after a wrapped signature, which
  `opening_brace` calls a violation. Every layout rule is therefore *disabled* in `.swiftlint.yml`
  rather than tuned. Re-enable one and `make format` and `make lint` will each undo the other's
  work forever. Add layout preferences to `.swift-format`, never to `.swiftlint.yml`.
- **`.swift-format` must keep `"indentation": { "spaces": 4 }`.** The tool's default is 2, which
  disagrees with every file here — dropping the key reports ~7,000 violations that are all the
  config's fault.
- **SwiftLint runs `--strict`**, so a *warning* fails the build. That is deliberate: the config
  reports zero violations today, so anything it prints is new. Both configs carry a comment for
  every rule relaxed and why (`identifier_name` allows `to`, the frontmatter key; `large_tuple`
  allows the derived `(person:role:)` pair).
- **A skipped test needs `.enabled(if:)`, not `#require`.** A failed `#require` *fails* the test;
  it does not skip it. `SeededVaultTests` reads the real `~/Documents/Maillage` and must skip
  where there is none, which is every CI run.

## Layout

```
.github/workflows/ci.yml             format & lint, tests, app build
.swift-format / .swiftlint.yml       layout / semantics — see CI for why they're split
Makefile                             make check runs the pipeline locally
Scripts/check-build-parity.sh        the two build systems must agree on versions
App/Info.plist                       bundle id, version, NSAudioCaptureUsageDescription
maillage.xcodeproj/                  committed; shared Maillage scheme
Sources/Maillage/MaillageApp.swift   @main, WindowGroup, menu commands (no key equivalents)
Sources/MaillageCore/
├── Design/     Theme.swift (tokens), Components.swift (Card, Pill, EntityAvatar, EntityLink, SidebarRow, …)
├── Model/      Entity, Person, Organization, Project, Relation, ProjectMembership, Wikilink, CalendarDay
├── Vault/      VaultLocation, FrontmatterCodec, VaultReader, VaultWriter, ImageSquarer
├── Store/      VaultStore — single source of truth
└── Views/      RootView, SidebarView, CenterPane, EntityDetails, GraphGeometry, Editors,
                CommandPalette, VaultPicker, and the four subject views (EgoGraphView,
                OrganizationBubblesView, OrganizationBoardView, ProjectRosterView)
```

The centre pane picks its representation from what's selected, since each selection is a different
question: **nothing** gets `OrganizationBubblesView` (one circle per employer, headcount inside,
area ∝ headcount), an **organization** gets `OrganizationBoardView` (a card per project listing who
staffs it), a **person** gets `EgoGraphView` (them centred, direct relations as labelled spokes),
and a **project** gets `ProjectRosterView`.

All four are **laid out, never simulated** — the two graphs from computed geometry
(`Views/GraphGeometry.swift` holds the shared pieces, `BubblePacking` and `EgoLayout` the per-view
layout, all unit-tested without a window), the two rosters from a stack. That is why there is no
graph library in the stack table: a force layout settles somewhere slightly different on every
launch, and "Acme is the big one in the middle" has to stay true between launches to be worth
reading.

The app target is a thin `@main` shell; everything testable lives in `MaillageCore`.

## Vault format

`~/Documents/Maillage` (configurable), one file per entity:

```
people/marie-dupont.md      organizations/acme-corp.md
people/_head-of-aa.md       projects/maillage.md          .maillage/config.yaml

assets/people/marie-dupont.png          assets/organizations/acme-corp.png
assets/projects/maillage.png
```

```markdown
---
id: marie-dupont
type: person
firstname: Marie
lastname: Dupont
email: marie@example.com
role: Head of Engineering
placeholder: false
organization: "[[acme-corp]]"
projects:
  - to: "[[maillage]]"
    role: Lead
  - "[[atlas]]"
relations:
  - to: "[[jean-martin]]"
    label: manager of
created: '2026-08-06'
---

Met at the Paris conference.
```

## Rules

These are invariants, not preferences — the tests enforce most of them.

- **Relations are one-way; backlinks are derived.** A relation is written *only* to the source
  person's file. Never write an inverse edge. `VaultStore.rebuildBacklinks()` inverts them in
  memory so the target can show "Referenced by", exactly like Obsidian.
- **Never hardcode a color, radius, spacing or font in a view.** Reference `Theme`. Both light
  and dark are resolved inside `Theme.adaptive`, so use sites never branch on appearance.
- **The cursor says what's clickable.** `.buttonStyle(.plain)` installs no tracking area, so
  AppKit leaves the arrow over every control in `Components.swift` unless told otherwise. Each
  one applies `clickableCursor()` itself (text inputs `textCursor()`), so a new button is
  clickable-looking by construction. Pass `clickableCursor(false)` when a control is only
  sometimes clickable — a disabled button or an action-less `Pill` — since a hand promises a
  click that does nothing. In the two graphs the `Canvas` draws only the edges and every node is
  its own SwiftUI view, so each node carries its own `.onHover` and `.clickableCursor` — attached
  *before* `.position`, since `.position` returns a pane-sized view and anything interactive on
  its result claims the whole pane.
- **A text input's box is bigger than its `TextField`.** Padding, border and placeholder are
  drawn around it, so a click near the edge misses the input and the field reads as dead.
  Whatever draws the box also claims it: `contentShape` plus `onTapGesture` setting the field's
  own `@FocusState`. `RoleField` in `Editors.swift` is the worked example.
- **Membership lives on the person** (`organization:`, `projects:`), never duplicated onto the
  org or project. Org/project member lists are derived by scanning people.
- **One organization per person, and one per project.** `organization:` is singular on both,
  because the People graph clusters on a person's employer and a cluster needs exactly one key
  per node, and because a project belongs to whoever owns the work — so
  `VaultStore.projects(inOrganization:)` partitions the projects rather than overlapping and a
  project shows on exactly one board. On both types the retired plural `organizations:` still
  decodes (first entry wins) so old vaults load; only `organization:` is ever written, so a file
  migrates the next time it is saved.
- **A project role lives on the person's project entry**, never on the project. An entry is a
  bare `"[[id]]"` until a role is set, then a `to:`/`role:` mapping — so adding a role rewrites
  one person's file and nothing else. Plain free text, entered in a bare `RoleField` — unlike a
  relation label, a role is what one person does on one project and is nearly always typed
  fresh, so there is no suggestion menu. `VaultStore.usedProjectRoles` still derives the
  vocabulary and is tested, but nothing in the UI reads it.
- **Membership is edited in the editor sheets, never inline in a pane.** Both ends offer it —
  `ProjectEditor` staffs a project, `PersonEditor` picks a person's projects — and both apply on
  save, so an abandoned sheet writes nothing. `VaultStore.setParticipants(ofProject:to:)` takes
  the whole intended roster and writes only the people whose entry actually changed. Detail and
  centre panes are display-only.
- **A logo is a file, not a field.** `assets/<kind>/<id>.png`, and its presence *is* the fact —
  `VaultStore.logoIDs` is derived by scanning `assets/` at load, like backlinks and membership, so
  there is no `logo:` key that can point at a deleted file and dropping a PNG in via Finder works.
  Partitioned by kind because ids only collide *across* kinds (`availableID` checks one folder, so
  `people/acme.md` and `projects/acme.md` can coexist). Always 512×512 centre-cropped PNG from
  `ImageSquarer`, which is the single place the format, the size and the crop are decided —
  anything macOS can decode goes in, including SVG, and PNG is the only lossless format with
  alpha it can write. Every circle standing for an entity is an `EntityAvatar`, which falls back
  to the kind's SF Symbol on a disc in the kind's `Theme` hue, so colour coding survives as the
  default. Picked in the editors and applied **on save**, like membership.
- **A link to an entity is an `EntityLink`, not a `Pill`.** Avatar plus name, underlined on hover.
  A pill's tinted capsule was both the affordance *and* the identification; a logo identifies
  better, and two capsules per row crowded out the role beside them — which on a roster is what
  the pane is read for. `Pill` stays for what isn't an entity: relation labels, and the removable
  tokens in the editors.
- **The filename is the identity.** `id` is the filename slug and the only link target;
  frontmatter `id` disagreeing with the filename loses. Renaming therefore *must* go through
  `VaultWriter.rename`, which rewrites every inbound `[[id]]` and moves the logo with the
  markdown — including when `resolvePlaceholder` turns `_head-of-aa` into a real slug.
- **Dates are `CalendarDay`, never `Date`.** Yams serializes `Date` as a UTC timestamp, which
  shifts the day backward for anyone east of UTC. `CalendarDay` writes `'yyyy-MM-dd'`.
- **Writes are atomic** (temp file + `replaceItemAt`) and go through `VaultStore`, so memory and
  disk never diverge. Assets included: `VaultWriter.writeAtomically` takes `Data`, so an
  interrupted save can no more leave half a PNG than half a profile.
- **A malformed file is an issue, not a crash.** `VaultReader` collects `VaultLoadIssue`s and
  loads everything else; the sidebar surfaces them. A logo that won't decode returns `nil` from
  `VaultStore.logo(kind:id:)` and the avatar falls back to its glyph — a bad image is reported at
  import, where someone chose it and can pick another.
- **Placeholder people** are for "you should meet the head of AA" — no name, a `descriptor`, and
  an `_` filename prefix. Resolving one renames the file and relinks.
- **No keyboard shortcuts.** The app declares no `keyboardShortcut` anywhere, and no UI text
  names a key. It had a full set — ⌘N, ⌘K, ⌘R, ⌥⌘0 — and they were removed because they didn't
  work in practice: a key printed in a menu's right-hand column that then doesn't fire is worse
  than no key, since it teaches a gesture and then makes someone doubt their keyboard. Every
  action stays reachable by pointer (the sidebar's per-section "+", the centre pane's pencil and
  chevron) and by menu item, so nothing was lost with them. Don't add one back without checking
  it actually fires in the running app.

<!-- rtk-instructions v2 -->
# RTK (Rust Token Killer) - Token-Optimized Commands

## Golden Rule

**Always prefix commands with `rtk`**. If RTK has a dedicated filter, it uses it. If not, it passes through unchanged. This means RTK is always safe to use.

**Important**: Even in command chains with `&&`, use `rtk`:
```bash
# ❌ Wrong
git add . && git commit -m "msg" && git push

# ✅ Correct
rtk git add . && rtk git commit -m "msg" && rtk git push
```

## RTK Commands by Workflow

### Build & Compile (80-90% savings)
```bash
rtk cargo build         # Cargo build output
rtk cargo check         # Cargo check output
rtk cargo clippy        # Clippy warnings grouped by file (80%)
rtk tsc                 # TypeScript errors grouped by file/code (83%)
rtk lint                # ESLint/Biome violations grouped (84%)
rtk prettier --check    # Files needing format only (70%)
rtk next build          # Next.js build with route metrics (87%)
```

### Test (60-99% savings)
```bash
rtk cargo test          # Cargo test failures only (90%)
rtk go test             # Go test failures only (90%)
rtk jest                # Jest failures only (99.5%)
rtk vitest              # Vitest failures only (99.5%)
rtk playwright test     # Playwright failures only (94%)
rtk pytest              # Python test failures only (90%)
rtk rake test           # Ruby test failures only (90%)
rtk rspec               # RSpec test failures only (60%)
rtk test <cmd>          # Generic test wrapper - failures only
```

### Git (59-80% savings)
```bash
rtk git status          # Compact status
rtk git log             # Compact log (works with all git flags)
rtk git diff            # Compact diff (80%)
rtk git show            # Compact show (80%)
rtk git add             # Ultra-compact confirmations (59%)
rtk git commit          # Ultra-compact confirmations (59%)
rtk git push            # Ultra-compact confirmations
rtk git pull            # Ultra-compact confirmations
rtk git branch          # Compact branch list
rtk git fetch           # Compact fetch
rtk git stash           # Compact stash
rtk git worktree        # Compact worktree
```

Note: Git passthrough works for ALL subcommands, even those not explicitly listed.

### GitHub (26-87% savings)
```bash
rtk gh pr view <num>    # Compact PR view (87%)
rtk gh pr checks        # Compact PR checks (79%)
rtk gh run list         # Compact workflow runs (82%)
rtk gh issue list       # Compact issue list (80%)
rtk gh api              # Compact API responses (26%)
```

### JavaScript/TypeScript Tooling (70-90% savings)
```bash
rtk pnpm list           # Compact dependency tree (70%)
rtk pnpm outdated       # Compact outdated packages (80%)
rtk pnpm install        # Compact install output (90%)
rtk npm run <script>    # Compact npm script output
rtk npx <cmd>           # Compact npx command output
rtk prisma              # Prisma without ASCII art (88%)
rtk uv run <cmd>        # Compact uv project command output
```

### Files & Search (60-75% savings)
```bash
rtk ls <path>           # Tree format, compact (65%)
rtk read <file>         # Code reading with filtering (60%)
rtk grep <pattern>      # Search grouped by file (75%). Format flags (-c, -l, -L, -o, -Z) run raw.
rtk find <pattern>      # Find grouped by directory (70%)
```

### Analysis & Debug (70-90% savings)
```bash
rtk err <cmd>           # Filter errors only from any command
rtk log <file>          # Deduplicated logs with counts
rtk json <file>         # JSON structure without values
rtk deps                # Dependency overview
rtk env                 # Environment variables compact
rtk summary <cmd>       # Smart summary of command output
rtk diff                # Ultra-compact diffs
```

### Infrastructure (85% savings)
```bash
rtk docker ps           # Compact container list
rtk docker images       # Compact image list
rtk docker logs <c>     # Deduplicated logs
rtk kubectl get         # Compact resource list
rtk kubectl logs        # Deduplicated pod logs
```

### Network (65-70% savings)
```bash
rtk curl <url>          # Compact HTTP responses (70%)
rtk wget <url>          # Compact download output (65%)
```

### Meta Commands
```bash
rtk gain                # View token savings statistics
rtk gain --history      # View command history with savings
rtk discover            # Analyze Claude Code sessions for missed RTK usage
rtk proxy <cmd>         # Run command without filtering (for debugging)
rtk init                # Add RTK instructions to CLAUDE.md
rtk init --global       # Add RTK to ~/.claude/CLAUDE.md
```

## Token Savings Overview

| Category | Commands | Typical Savings |
|----------|----------|-----------------|
| Tests | vitest, playwright, cargo test | 90-99% |
| Build | next, tsc, lint, prettier | 70-87% |
| Git | status, log, diff, add, commit | 59-80% |
| GitHub | gh pr, gh run, gh issue | 26-87% |
| Package Managers | pnpm, npm, npx | 70-90% |
| Files | ls, read, grep, find | 60-75% |
| Infrastructure | docker, kubectl | 85% |
| Network | curl, wget | 65-70% |

Overall average: **60-90% token reduction** on common development operations.
<!-- /rtk-instructions -->
