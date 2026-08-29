# Architecture

This document explains how maillage is actually built at runtime: the four layers, the codec that
turns a markdown file into a value and back, the server that owns the vault, and the layout
algorithms behind the two graphs.

It does **not** cover the build, CI, releasing, the vault file format, or the app's invariant
rules. Those are documented exhaustively in [CLAUDE.md](CLAUDE.md), and this doc links out to it
rather than repeating it. Read that first if you need to run or ship the app; read this one to
understand how the code that runs is put together.

## Layer map

```
  browser                                     │  node
                                              │
  Views          App, Sidebar, CenterPane     │
  src/views/     EntityDetails, NetworkGraph  │
                 panes, Editors, Palette      │
                        │                     │
                        │ read / mutate       │
                        ▼                     │
  Store          VaultProvider (context)      │
  src/vault/     snapshot + derived indexes   │
                        │                     │
                        │ fetch               │
                        ├─────────────────────┤
                        │                     ▼
  Transport      api.ts  ───── HTTP ─────►  server/index.ts
                                              │
                                              ▼
                                            server/vault.ts
                                            shared/frontmatter.ts
                                              │
                                              ▼
                                            people/ organizations/ projects/
                                            assets/**.png    (the folder on disk)
```

Four layers, each with one job:

- **Views** render whatever the store currently holds and route every mutation back through it.
  No view calls `fetch` directly.
- **Store** (`src/vault/store.tsx`) is the client's single source of truth: one `VaultSnapshot`,
  the indexes derived from it, and every mutation.
- **Transport** is a dozen typed `fetch` wrappers. Every mutating call answers with the _whole_
  vault, freshly read, so the client can never hold a snapshot that disagrees with the disk.
- **Vault** (`server/vault.ts` plus the codec in `shared/`) is where markdown-with-frontmatter
  becomes values and back, and where the atomic-write guarantee lives. It is the only module in
  the app that touches the filesystem.

The line down the middle is the interesting one. Everything that has to be _consistent_ — a
rename that repoints thirty files, a delete that scrubs every reference, a roster diff — is on the
server side of it: one function, one process. Everything that has to be _fast_ — sorting,
grouping, laying out a graph — is on the browser side, recomputed from the snapshot. Nothing is
cached in between, which is why there is no cache-invalidation code anywhere in this repo.

## Shared layer

`shared/` — imported by both halves, so it holds no `document` and no `node:fs`.

### The model

Every entity is a plain object with a `kind` discriminant (`'person' | 'organization' |
'project'`), an `id` that is always equal to the vault filename stem, a `body` holding the free
markdown below the frontmatter, and its own fields. `AnyEntity` is the union and TypeScript
narrows it on `kind`, so there is no type-erasure wrapper anywhere.

Cross-entity links are never nested objects and never wrapper types: an `organization` field is
just an `EntityID`, and the `[[…]]` syntax exists only inside the codec. `parseWikilink` decodes
tolerantly — it accepts a bare id and strips Obsidian's `[[id|display]]` and `[[id#heading]]`
forms down to the target — while only the bare `[[id]]` is ever written. `slugify` is the one
place a display name becomes an id: fold diacritics and case, collapse non-alphanumerics to single
dashes, trim the ends.

```
STORED (written to a file)
  Person   --organization------------------------> Organization
  Person   --projects: ProjectMembership----------> Project
  Person   --relations: Relation, one-way---------> Person
  Project  --organization------------------------> Organization

DERIVED (computed in memory, never persisted)
  Organization <-- members -------- scans every Person.organization
  Project      <-- participants --- scans every Person.projects
  Person       <-- backlinks ------ inverts every Person.relations
```

**Membership and relations live on exactly one side of the link**, and the other side's view of
them is always derived. That is not an optimisation. It is the reason a fact about Marie is only
ever in `people/marie-dupont.md`, and so can never be half-updated.

`CalendarDay` is a `'YYYY-MM-DD'` string rather than a `Date`, because a `Date` is a UTC instant
and serializing one shifts the calendar day backward for anyone east of UTC. String compare is
also the correct chronological compare for that format, so ordering needs no code at all.

### The codec

`shared/frontmatter.ts` is the whole `---\nyaml\n---\nbody` format in one place, and the one module
in this repo with a genuinely hard requirement: **decode then encode must reproduce the file byte
for byte.** A vault is a git repository. A save that re-quoted a scalar or re-indented a list would
put a diff on every file it touched, forever.

Holding to that against the files a vault already contains took three decisions, all tested:

- `indentSeq: false` — sequences sit flush with their key, not indented under it.
- `lineWidth: 0` — a long list of wikilinks is never folded mid-array.
- An explicit quoting pass. A wikilink opens with `[` so it _must_ be quoted, and `yaml` would
  reach for double quotes; a `YYYY-MM-DD` day needs no quotes at all under YAML 1.2 and `yaml`
  would emit it bare — but a bare date is a timestamp to any reader still on YAML 1.1, which is
  exactly the ambiguity `CalendarDay` exists to avoid. Both are pinned to single quotes by walking
  the document and setting `Scalar.QUOTE_SINGLE`, rather than hoping a heuristic agrees.

Key order comes from construction order, so `frontmatterOf` reads as the on-disk key order.
`ProjectMembership` encodes back to a bare `'[[id]]'` whenever its role is empty, so adding a role
is the only thing that ever expands a file's YAML.

`splitFrontmatter` returns the body trimmed, and `joinFrontmatter` always writes exactly one blank
line after the closing fence and one newline at the end — the shape existing vault files already
have, which is why they round-trip unchanged rather than gaining or losing a line on first save.

## Server

`readVault` walks each kind's directory, decodes every file, and — the identity rule made concrete
— **overwrites whatever `id:` the frontmatter claims with the actual filename stem**. A parse
failure becomes a `VaultLoadIssue` and everything else still loads: one bad file never takes down
the vault. Logo ids come from scanning `assets/`, so a logo's presence on disk _is_ the fact and
there is no field that can point at a file that is gone.

Everything written goes through one primitive: write the bytes to a same-directory temp file, then
`rename` it into place. Same directory means the rename is atomic, so a crash mid-save leaves the
destination wholly old or wholly new, never half written. Entity files and PNGs alike.

Three operations touch more than their own file, and are the reason the server exists at all
rather than the browser writing through a thin proxy:

- **`renameEntity`** rejects a target that already exists, re-encodes the entity under the new id,
  deletes the old file, moves the logo across, then walks every person rewriting `relations[].to`,
  `organization` and `projects[].to`, and every project rewriting `organization`. Renaming is the
  one operation that has to repair every inbound reference, because `id` is the only link target
  there is.
- **`deleteEntity`** does the same walk in reverse: the file and its logo go, then every relation,
  membership, employer and project owner pointing at it is scrubbed. No soft delete.
- **`setParticipants`** is a diff, not a replace. Given the _entire_ intended roster it adds a
  membership for anyone new, updates a role only if it actually changed, removes the membership for
  anyone dropped — and writes only the people whose entry differs, compared by re-encoding.

`resolvePlaceholder` composes two of these: fill in a placeholder's real identity, then rename to
the slug that identity implies, so "meeting the head of AA" ends as one coherent file move rather
than a stale underscore-prefixed filename sitting beside a real name.

`assertSafeID` is the trust boundary. Ids arrive from the client, so a separator or a `..` here
would be a path traversal out of the vault.

`server/index.ts` is a path switch over `node:http`. `/api/*` is the vault;
`/assets/<dir>/<id>.png` serves a logo straight off disk; everything else is `dist/`, or Vite in
middleware mode when `MAILLAGE_DEV` is set — which is why development and production are the same
one process on the same one port, with no proxy and no CORS. It binds to `127.0.0.1` and
authenticates nothing, because nothing else can reach it.

## Client

`src/vault/store.tsx` holds the snapshot, the backlink index, the employer grouping and a set per
kind of which ids have logos, all `useMemo`'d off the snapshot. Every mutation runs through one
`apply` helper: call the API, take the fresh snapshot, or surface why it did not happen.

`src/vault/derived.ts` is every query the views make, as pure functions — `allPeople`,
`membersOfOrganization`, `participantsOfProject`, `peopleGroupedByOrganization`,
`usedRelationLabels`, and the rest. Nothing here is cached, and the sort orders are load-bearing:
a group's index in `peopleGroupedByOrganization` **is** its cluster colour, so a person's hue means
the same thing in the network graph as it does in the bubbles.

`CenterPane` switches on the selection alone, with no mode picker, because each selection is a
different question — see the table in [CLAUDE.md](CLAUDE.md). Selection itself is one `{kind, id}`
reference living in `App`, mirrored into `location.hash`, so a reload and the browser's own back
button both land where you were. It carries the kind because ids only collide _across_ kinds:
`people/acme.md` and `projects/acme.md` can both exist.

## The graphs

`src/graph/` is arithmetic, deliberately. There is no graph library in the stack table because a
force layout settles somewhere slightly different on every load, and "Acme is the big one in the
middle" has to stay true between loads to be worth reading. Every function here is pure and tested
without a browser.

### `geometry.ts`

`ringRadii` computes how large a ring can be in a given pane, treating the margins reserved for
labels as _caps_ (`min(desired, dimension × 0.18)`) rather than fixed reserves, so a narrow window
shrinks its margins before it shrinks the ring below a floor. It returns two radii, not one: a pane
is wider than it is tall, and a circle inscribed in a 16:9 pane leaves a third of the width empty
on each side while crowding every label into the middle third.

`onEllipse` places a point with angle 0 straight up and increasing clockwise, so labels read around
the ring the way numbers read around a clock face. `controlPoint` offsets a quadratic curve's
control point perpendicular to its chord by a share of its length. `trimmed` shortens an edge so it
meets a node's rim rather than vanishing underneath it. `arrowhead` builds its triangle from the
_curve's_ tangent at the tip, not the straight chord between the endpoints, so an arrowhead on a
bowed edge actually points along the curve.

### `network.ts` — traversal

`traverse(snapshot, rootID, depth)` walks the relation graph breadth-first, treating relations as
**undirected** for reachability — knowing someone is mutual even when only one file says so — while
each edge keeps its own direction. It returns each node's hop number and **every edge among the
people reached**, siblings included.

That last part is what the old one-hop ego graph could not do. It drew only spokes, so two
neighbours who knew each other looked exactly like two who did not, and a cluster, a triangle or a
bridge between two parts of a network was invisible. Edges joining the same pair are numbered
(`ordinal`, `siblings`) so the layout can bow them apart instead of stacking them.

A dangling relation target — a `[[…]]` with no file — is not walked to. A self-relation produces
neither a node nor an edge. Past `MAX_NODES` the traversal stops adding and reports how many it
left out, because a network drawing stops being a drawing long before it stops being complete.

### `egoLayout.ts` — concentric rings

1. The subject sits at the pane's centre.
2. Each hop gets its own ring. The outermost lands on `ringRadii`, so **at depth 1 this reduces to
   exactly the single ring the app has always drawn**. Inner rings are spaced from a floor of 45%
   rather than from zero: dividing the radius evenly squeezes the first ring — usually the busiest
   — into a third of the space while the outermost sits nearly empty.
3. Within a ring, nodes are ordered by (employer cluster index, display name, id), so colleagues sit
   adjacent and the order never changes between loads, then placed evenly at `2π·i/count`.
4. Node radius falls off with hop, so how far out someone is reads without counting rings.
5. Where more than one relation joins the same pair, each edge is bowed apart from its siblings by
   `pairSpread × (ordinal − (count−1)/2) × 2`. The sign is flipped for an edge stored in the
   reversed orientation: a perpendicular offset is measured from `from` towards `to`, so the two
   halves of a mutual relation — written as a→b and b→a — would otherwise bow to the same side and
   land back on top of each other. That was a real bug, and the tests caught it.
6. Each edge's label sits at `t = 0.62` along its own curve, not at the midpoint. Every spoke's true
   midpoint is the same distance from the subject, so at 0.5 the labels all land on one small circle
   and pile onto each other.

### `bubblePacking.ts` — the overview

1. Each group's radius is `min(44 + 26·√(headcount − 1), 150)`. Square-root growth ties _area_, not
   radius, to headcount; doubling the radius would otherwise imply 4× the people when it is 4× the
   ink.
2. Groups are sorted biggest-first (ties by name), with the "no employer" bucket always placed last
   regardless of size, so the largest actual company claims the centre and a bucket that is not a
   company never becomes the subject of the picture.
3. Each subsequent circle is placed by a **deterministic spiral sweep**: starting at a distance just
   clearing the first-placed circle, sweep 90 angles; if none of them clear every already-placed
   circle by `radius + other.radius + gap`, step the distance out by 3pt and sweep again. The
   loosest possible packing is every circle in a line, so it always terminates. No physics, no
   relaxation, no randomness: identical input always produces an identical layout, which is the
   whole point.
4. The finished cluster is fitted to the pane — bounding box, scale capped at 1.35 so a vault with
   one company doesn't balloon to fill the window, centred.

## Interaction in the network view

Depth changes the graph. Everything else — the relation-label legend, the employer legend, the
search box, hover — changes only what is **lit**, never where anything sits. Moving the picture
while someone is reading it costs them the picture.

Labels are shown for every edge below a small threshold and, above it, only for what is lit, since
past a dozen edges a full set of labels is a wall of overlapping words rather than information.

An edge is drawn dashed when it points _at_ the current subject, meaning the relation is written on
the other person's file. That is not decoration: it says which file to open in order to change it.

Pan and zoom are the SVG `viewBox` and about thirty lines. Clicking a node re-roots the graph on
them and pushes a breadcrumb, so following a chain is exploration rather than losing your place.

## Where to go next

- [CLAUDE.md](CLAUDE.md): running the app, the CI pipeline, releasing, the vault file format, and
  the invariant rules the test suite enforces.
- The test suite is the other half of this document. `shared/frontmatter.test.ts` is the format
  contract, `server/vault.test.ts` is the mutation contract, and `src/graph/graph.test.ts` is the
  layout contract.
