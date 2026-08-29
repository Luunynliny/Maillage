# maillage

A personal CRM with Obsidian's look and feel. People, organizations and projects live as
markdown files with YAML frontmatter; labeled one-way relations between people are visualized
as a multi-hop network clustered by employer.

It runs locally: one Node process serves the page and owns the vault folder.

## Stack

| Piece              | Choice                                                                                                                    |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| Language           | TypeScript, strict, ES modules                                                                                            |
| Client             | React 19 + Vite                                                                                                           |
| Server             | `node:http` on the standard library, no framework                                                                         |
| YAML               | [yaml](https://github.com/eemeli/yaml) (ISC)                                                                              |
| Markdown rendering | [react-markdown](https://github.com/remarkjs/react-markdown) + [remark-gfm](https://github.com/remarkjs/remark-gfm) (MIT) |
| Tests              | [Vitest](https://vitest.dev) (MIT), node environment, no DOM                                                              |
| Format             | Prettier (MIT). No linter — see CI                                                                                        |

**Open source first.** Every dependency added must be OSS with a permissive license, noted in
the table above with its license. The runtime dependency list is five packages and is meant to
stay that size; before adding one, check whether the platform already does it.

Deliberately absent, each for a reason worth keeping:

- **No graph library.** Both graphs are computed, never simulated — see the Rules below. A force
  layout is a physics engine you cannot reproduce; `src/graph/` is arithmetic over SVG.
- **No router.** Selection is one entity reference, mirrored into `location.hash` in ten lines.
- **No state library.** One React context holds the snapshot and the mutations.
- **No server framework.** `node:http` plus a path switch, and a five-entry mime map for `dist/`.
- **No image library.** Logo squaring runs on a `<canvas>` in the browser.
- **No linter.** Prettier owns layout, `tsc --noEmit` owns everything else.

## Running

```
npm ci
npm start        # builds the client, then serves it and the vault on localhost:3000
npm run dev      # the same server with Vite mounted inside it: one process, one port, HMR
```

`PORT` overrides the port. The vault path lives in `~/.config/maillage/config.json` and is
editable from the bottom of the sidebar; it defaults to `~/Documents/Maillage`.

Watch out for:

- **The server runs its TypeScript directly** — `node server/index.ts`, no build step. That works
  because Node strips types (natively on 24+, behind `--experimental-strip-types` on 22.6+), and
  it costs one constraint: `server/` and `shared/` may use **no enums, no namespaces and no
  parameter properties**, and every type-only import must say `import type`. `tsconfig.json` sets
  `erasableSyntaxOnly`, so `npm run typecheck` catches a violation rather than the server failing
  to boot. If this ever becomes more trouble than a build step, add `tsx`.
- **Relative imports carry their extension** (`./vault.ts`, `./App.tsx`). Node's ESM resolver
  requires it; Vite is happy either way. `allowImportingTsExtensions` makes TypeScript agree.
- **`shared/` is imported by both halves** and must therefore stay free of anything
  browser-only or Node-only: no `document`, no `node:fs`.
- **Vite is a devDependency the server imports**, but only on the development path, behind a
  dynamic `import()` guarded by `MAILLAGE_DEV`. A production install with `--omit=dev` still runs.

## Quality gates

| Command               | Does                                                           |
| --------------------- | -------------------------------------------------------------- |
| `npm run check`       | Everything CI runs before the build: format, types, tests      |
| `npm run format`      | Rewrites sources to match `.prettierrc` (CI only _checks_)     |
| `npm run typecheck`   | `tsc --noEmit`                                                 |
| `npm test`            | The suite, via Vitest                                          |
| `npm run build`       | The client bundle into `dist/`                                 |
| `npm run release:dry` | The version and notes a merge would produce. Publishes nothing |

**There is no linter, on purpose.** Prettier decides layout and TypeScript decides the rest; the
gap between them is small enough that a third tool would mostly generate opinions to configure
away. If one is added later it must not fight Prettier: two tools that each undo the other's
work is a configuration you never finish tuning.

**`shared/__fixtures__/` is excluded from Prettier.** Those files are real vault files, compared
byte for byte; reformatting them would silently change what the golden test asserts.

## CI

`.github/workflows/ci.yml` runs on every push and PR to `main` and `develop`, as a **chain of
stages** — cheapest gate first, and nothing downstream starts until everything upstream is green,
so a failure costs the least it can and its reason is never buried under an unrelated one.

```
quality ┐
commits ├─→ test ─→ build ─→ release      release: push to main only
branch  ┘
```

| Stage            | Runs                                                       | Guards                                                                    |
| ---------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------- |
| Format & types   | `prettier --check`, `tsc --noEmit`                         | Needs no build, so it reports in under a minute                           |
| Commit messages  | `commitlint` on the PR title and on every commit in the PR | That a merge will actually release something — see Releasing. PRs only    |
| Branch name      | `<type>/<slug>` against commitlint's type list             | That the branch and the commit type it produces stay in step. PRs only    |
| Tests            | `vitest run`                                               | The suite, golden files included                                          |
| Build the client | `vite build`                                               | That every import still resolves — types passing is not the same question |
| Release          | `semantic-release`                                         | Publishes. Push to `main` only                                            |

Every job is `ubuntu-latest` and Node is pinned to 24 by `NODE_VERSION`.

`test` needs all three of the first stage, and carries `if: ${{ !failure() && !cancelled() }}`
because `commits` and `branch-name` are skipped on a `push` — without it, a skipped need would
skip the whole rest of the chain. `build` carries it for the same reason.

**No check is _required_ yet.** The repo is private on a free plan, so branch protection returns
403 (`Upgrade to GitHub Pro or make this repository public`). Every gate above is advisory until
the repo goes public or Pro — a red PR can still be merged. That is a real gap, not an oversight.
Once either is true, mark `Format & types`, `Commit messages`, `Branch name`, `Tests` and
`Build the client` required on `main`. Not `Release`: it only runs _after_ a merge, so requiring
it would block every PR on a job that cannot run yet.

## Releasing

Merging into `main` publishes a GitHub Release: generated notes and both source archives.
**Nothing is attached and nothing is built** — the app is source that runs with `npm ci &&
npm start`, so a release is its tag and its notes. Nothing about it is typed by hand: **the
version is computed from the commit messages**, which is why Conventional Commits are machinery
here rather than a style.

| Piece                        | Where                                                                          |
| ---------------------------- | ------------------------------------------------------------------------------ |
| Version, tag, notes, publish | `semantic-release`, config in `.releaserc.json`, pinned in `package-lock.json` |
| Message rules                | `commitlint.config.js` (`config-conventional`, `header-max-length` 100)        |

The bump comes from the commit type: `fix:` → patch, `feat:` → minor, `feat!:` or a
`BREAKING CHANGE:` footer → major. Everything else (`chore:`, `ci:`, `docs:`, `style:`, `test:`,
`refactor:`) releases **nothing** — which is correct, and also the most common reason a merge
lands and no release appears.

**`.releaserc.json` must keep `"preset": "conventionalcommits"` on both the analyzer and the
notes generator.** semantic-release defaults to the `angular` preset, whose parser predates the
`!` breaking-change shorthand — and it does not merely ignore the `!`, it fails to parse the
header at all. So under the default, `feat!: …` is not a major release, and not a minor one
either: it is **no release**, silently, on a merge that looked correct all the way through.
`commitlint`'s `config-conventional` accepts `!` happily, so the two tools disagree without a
word between them, and the gate that would have caught it is the one job that cannot run on the
commit that matters.

**And `conventional-changelog-conventionalcommits` must stay pinned on the `8.x` line**, as a
direct devDependency rather than a hoisted transitive one. `release-notes-generator@14` is built
on the v8 writer; hand it a v9 or v10 preset and the _analyzer_ still computes the right bump
while the _writer_ silently emits nothing. That is how v1.0.0 shipped with a version heading and
an empty body under it.

Both of these failed quietly, one after the other, on the same release. `release.test.ts` runs
the real `.releaserc.json` through both plugins and asserts what each title form produces —
including that anything which releases at all also gets notes written under it. It fails on both
of the bugs above. Do not delete it to make a dependency bump go green.

Preview any of this before merging with `npm run release:dry`.

The repository settings this depends on are already set, and all three matter:

| Setting →                      | Value        | Because                                                                                                                      |
| ------------------------------ | ------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| Merge commits / rebase merging | **off**      | Only squashing puts one conventional commit on `main`                                                                        |
| Squash commit title            | **PR title** | The title CI lints is the one that gets parsed. `COMMIT_OR_PR_TITLE` silently uses the _commit's_ subject on a one-commit PR |
| Squash commit message          | **blank**    | See below — a PR body is prose, and `commit-analyzer` reads a commit body as data                                            |

Watch out for:

- **The PR title is the release note.** Merges into `main` are squash-only, so the title becomes
  the single commit on `main` and is the only thing `commit-analyzer` reads. A perfectly
  conventional branch under a `chore:` PR title ships nothing. Re-enabling merge commits changes
  what gets parsed — every commit, not the title — and makes the notes unreadable.
- **Leave the squash message blank; never `PR_BODY`.** A commit _body_ is parsed, not quoted: a
  `BREAKING CHANGE:` line anywhere in it forces a major release, and anything shaped like
  `thing#ref` becomes a "closes" link. PR #1's body documents Obsidian's `[[id#heading]]` syntax,
  which with `PR_BODY` set made the release notes claim to close issue `id#heading` — a repository
  that does not exist. Prose written for people should not be able to decide a version number.
- **Never edit a version to release, and never commit a changelog.** `package.json`'s `version` is
  `0.0.0-unused` and nothing reads it; the released version lives on the git tag. No commit lands
  on `main` from a release — no `CHANGELOG.md`, no `chore(release)` — because the release body _is_
  the changelog and a bot commit on `main` would force a `main`→`develop` back-merge after every
  ship. `main` stays linear; `develop` never diverges.
- **Don't cancel a running release.** semantic-release pushes the tag _before_ calling its publish
  plugins and cannot roll back, so a cancel in that window leaves a tag on `main` with no release
  and no commits left for the next run to analyze. Hence the `release` job's own `release-main`
  concurrency group with `cancel-in-progress: false`, deliberately not the workflow's cancelling
  one.

## Layout

```
.github/workflows/ci.yml             staged: quality/commits/branch → test → build → release
.prettierrc / .prettierignore        the only formatter; fixtures are excluded on purpose
.releaserc.json / commitlint.config.js   what a merge to main publishes / what a message must be
package.json                         one package: the app and the release tooling
tsconfig.json  vite.config.ts  index.html

shared/          imported by BOTH halves — no DOM, no fs
├── types.ts         Person, Organization, Project, Relation, ProjectMembership, snapshot
├── wikilink.ts      parse / format / slugify
├── calendarDay.ts   'YYYY-MM-DD' in and out
├── frontmatter.ts   the ---\nyaml\n---\nbody format, both directions
└── __fixtures__/    real vault files, compared byte for byte by frontmatter.test.ts

server/
├── index.ts     http: /api, /assets, and dist/ (or Vite, in dev)
├── vault.ts     the only module that touches the filesystem
└── config.ts    where the vault is

src/
├── design/      theme.css (tokens) + components.tsx (every primitive)
├── vault/       api.ts, store.tsx (the context), derived.ts (every computed query), image.ts
├── graph/       geometry.ts, network.ts (traversal), egoLayout.ts, bubblePacking.ts
└── views/       App is in src/App.tsx; Sidebar, CenterPane, EntityDetails, NetworkGraph,
                 panes.tsx (bubbles / board / roster), CommandPalette, Editors, VaultPicker
```

The centre pane picks its representation from what's selected, since each selection is a
different question: **nothing** gets the organization bubbles (one circle per employer, headcount
inside, area ∝ headcount), an **organization** gets its project board (a card per project listing
who staffs it), a **person** gets the network graph, and a **project** gets its roster.

## Vault format

`~/Documents/Maillage` (configurable), one file per entity:

```
people/marie-dupont.md      organizations/acme-corp.md
people/_head-of-aa.md       projects/maillage.md

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
organization: '[[acme-corp]]'
projects:
  - to: '[[maillage]]'
    role: Lead
  - '[[atlas]]'
relations:
  - to: '[[jean-martin]]'
    label: manager of
created: '2026-08-06'
---

Met at the Paris conference.
```

The reader walks only these three directories and `assets/`. Anything else in the folder is
ignored rather than an error, so keeping unrelated notes beside the vault is fine.

## Rules

These are invariants, not preferences — the tests enforce most of them.

- **The frontmatter codec round-trips byte for byte.** A vault is a git repository, so a save that
  rewrote quoting, key order or list indentation would produce a diff nobody asked for on every
  file it touched. `shared/frontmatter.test.ts` decodes and re-encodes every file in
  `shared/__fixtures__/vault` and asserts byte equality. Sequences sit flush with their key
  (`indentSeq: false`), lines never wrap (`lineWidth: 0`), keys come from construction order, and
  wikilinks and days are explicitly single-quoted rather than left to a heuristic. A failure there
  means the codec is broken, not that the fixture needs updating.
- **The server owns every mutation that touches more than one file.** Rename with relinking,
  delete with scrubbing, and the roster diff live in `server/vault.ts`. A client doing them over
  several requests could be interrupted halfway and leave the vault inconsistent.
- **Every mutation answers with the whole vault, freshly read.** There is no client-side cache to
  invalidate and no partial update to get wrong. At this size a re-read is a couple of
  milliseconds; if a vault ever gets big enough to notice, return a delta then, not before.
- **Writes are atomic** — a temp file in the same directory, then `rename` — and everything goes
  through the one function, logos included. An interrupted save can no more leave half a PNG than
  half a profile.
- **Relations are one-way; backlinks are derived.** A relation is written _only_ to the source
  person's file. Never write an inverse edge. `buildBacklinks` inverts them in memory so the
  target can show "Referenced by", exactly like Obsidian.
- **Never hardcode a color, radius, spacing or font in a component.** Every one is a
  `var(--token)` from `src/design/theme.css`, which resolves light and dark in one place so no
  component branches on appearance.
- **Membership lives on the person** (`organization:`, `projects:`), never duplicated onto the
  org or project. Org and project member lists are derived by scanning people.
- **One organization per person, and one per project.** `organization:` is singular on both,
  because the graphs cluster on a person's employer and a cluster needs exactly one key per node,
  and because a project belongs to whoever owns the work — so `projectsInOrganization` partitions
  the projects rather than overlapping and a project shows on exactly one board. On both types the
  retired plural `organizations:` still decodes (first entry wins) so old vaults load; only
  `organization:` is ever written, so a file migrates the next time it is saved.
- **A project role lives on the person's project entry**, never on the project. An entry is a
  bare `'[[id]]'` until a role is set, then a `to:`/`role:` mapping — so adding a role rewrites
  one person's file and nothing else, and an untouched entry stays byte-identical. Plain free
  text: unlike a relation label, a role is what one person does on one project and is nearly
  always typed fresh, so there is no suggestion menu. `usedProjectRoles` still derives the
  vocabulary and is tested, but nothing in the UI reads it.
- **Membership is edited in the editor sheets, never inline in a pane.** Both ends offer it —
  the project editor staffs a project, the person editor picks a person's projects — and both
  apply on save, so an abandoned sheet writes nothing. `setParticipants` takes the whole intended
  roster and writes only the people whose entry actually changed. Detail and centre panes are
  display-only.
- **A logo is a file, not a field.** `assets/<kind>/<id>.png`, and its presence _is_ the fact —
  `logoIDs` is derived by scanning `assets/` at load, like backlinks and membership, so there is
  no `logo:` key that can point at a deleted file and dropping a PNG in via Finder works.
  Partitioned by kind because ids only collide _across_ kinds (`availableID` checks one folder, so
  `people/acme.md` and `projects/acme.md` can coexist). Always 512×512 centre-cropped PNG from
  `src/vault/image.ts`, which is the single place the format, the size and the crop are decided.
  Every circle standing for an entity is an `EntityAvatar`, which falls back to the kind's glyph
  on a disc in the kind's hue, so colour coding survives as the default. Picked in the editors and
  applied **on save**, like membership.
- **A link to an entity is an `EntityLink`, not a `Pill`.** Avatar plus name, underlined on hover.
  A pill's tinted capsule was both the affordance _and_ the identification; a logo identifies
  better, and two capsules per row crowded out the role beside them — which on a roster is what
  the pane is read for. `Pill` stays for what isn't an entity: relation labels, the graph legend,
  and the removable tokens in the editors.
- **The filename is the identity.** `id` is the filename slug and the only link target;
  frontmatter `id` disagreeing with the filename loses. Renaming therefore _must_ go through
  `renameEntity`, which rewrites every inbound `[[id]]` and moves the logo with the markdown —
  including when `resolvePlaceholder` turns `_head-of-aa` into a real slug.
- **Dates are `CalendarDay`, never `Date`.** A `Date` is a UTC instant, and serializing one
  shifts the calendar day backward for anyone east of UTC. A `CalendarDay` is a `'yyyy-MM-dd'`
  string, which also makes string compare the correct chronological compare.
- **A malformed file is an issue, not a crash.** `readVault` collects `VaultLoadIssue`s and loads
  everything else; the sidebar surfaces them.
- **Placeholder people** are for "you should meet the head of AA" — no name, a `descriptor`, and
  an `_` filename prefix. Resolving one renames the file and relinks.
- **The graphs are laid out, never simulated.** A force layout settles somewhere slightly
  different on every load, and "Acme is the big one" has to stay true between loads to be worth
  reading. `layoutEgo` places each hop on its own concentric ring, ordered by employer then name
  then id; `packBubbles` places circles by a deterministic spiral sweep. Both are pure functions
  with tests that assert the same input gives byte-identical output.
- **Filters dim; they never relayout.** Depth changes the graph, but the label legend, the
  organization legend and the search box only change what is lit. Moving the picture while
  someone is reading it costs them the picture.
- **Every commit is `type: description`**, every branch is `type/slug`, and every PR title is
  `type: description` — one vocabulary, checked by `commitlint` in CI. This is not tidiness: the
  squashed PR title is what decides the next version and what people read in the release notes.
  See Releasing for which types release and which don't.
- **The version is never written by a human.** `semantic-release` derives it from the commits and
  it lives on the git tag; `package.json`'s `version` is a placeholder nothing reads.
