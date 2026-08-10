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
| Tests, quick compile check | `rtk swift test` | ~0.1s. Xcode's runner takes ~80s for the same 43 tests |
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
- Signing is manual and ad-hoc (`CODE_SIGN_IDENTITY = "-"`), because this machine has no
  Developer ID. The App Sandbox is **off**, so the vault stays a plain readable folder; there is
  no entitlements file yet. The audio phase will need one (`App/Maillage.entitlements`, referenced
  by `CODE_SIGN_ENTITLEMENTS`) alongside the `NSAudioCaptureUsageDescription` already in
  `App/Info.plist`.

Both tools need Xcode's toolchain rather than Command Line Tools. `xcode-select` is already
pointed at Xcode; if a fresh machine errors out, run
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

## Layout

```
App/Info.plist                       bundle id, version, NSAudioCaptureUsageDescription
maillage.xcodeproj/                  committed; shared Maillage scheme
Sources/Maillage/MaillageApp.swift   @main, WindowGroup, menu commands (⌘N, ⌘K, ⌘R)
Sources/MaillageCore/
├── Design/     Theme.swift (tokens), Components.swift (Card, Pill, SidebarRow, …)
├── Model/      Entity, Person, Organization, Project, Relation, ProjectMembership, Wikilink, CalendarDay
├── Vault/      VaultLocation, FrontmatterCodec, VaultReader, VaultWriter
├── Store/      VaultStore — single source of truth
└── Views/      RootView, SidebarView, CenterPane, DetailView, Editors, CommandPalette, VaultPicker
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
  click that does nothing. The graph is the exception and resolves per-point with
  `onContinuousHover`, because one `Canvas` holds every node.
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
  one person's file and nothing else. Free text, and the vocabulary offered back is derived from
  use (`VaultStore.usedProjectRoles`), like relation labels.
- **Membership is edited in the editor sheets, never inline in a pane.** Both ends offer it —
  `ProjectEditor` staffs a project, `PersonEditor` picks a person's projects — and both apply on
  save, so an abandoned sheet writes nothing. `VaultStore.setParticipants(ofProject:to:)` takes
  the whole intended roster and writes only the people whose entry actually changed. Detail and
  centre panes are display-only.
- **The filename is the identity.** `id` is the filename slug and the only link target;
  frontmatter `id` disagreeing with the filename loses. Renaming therefore *must* go through
  `VaultWriter.rename`, which rewrites every inbound `[[id]]`.
- **Dates are `CalendarDay`, never `Date`.** Yams serializes `Date` as a UTC timestamp, which
  shifts the day backward for anyone east of UTC. `CalendarDay` writes `'yyyy-MM-dd'`.
- **Writes are atomic** (temp file + `replaceItemAt`) and go through `VaultStore`, so memory and
  disk never diverge.
- **A malformed file is an issue, not a crash.** `VaultReader` collects `VaultLoadIssue`s and
  loads everything else; the sidebar surfaces them.
- **Placeholder people** are for "you should meet the head of AA" — no name, a `descriptor`, and
  an `_` filename prefix. Resolving one renames the file and relinks.

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
