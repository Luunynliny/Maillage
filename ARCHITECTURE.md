# Architecture

This document explains how maillage is actually built at runtime: the model layer, the
vault that stores everything as markdown, `VaultStore` as the single writer, the five
center-pane views and the layout algorithms behind the two graphs, and the meeting-recording
pipeline that turns raw audio into a transcript and summary on-device via MLX.

It does **not** cover build systems, CI, releasing, the vault file format, or the app's
invariant rules. Those are documented exhaustively in [CLAUDE.md](CLAUDE.md), and this doc
links out to it rather than repeating it. Read that first if you need to build or ship the
app; read this one to understand how the code that runs is put together.

## Layer map

```
 Views        RootView, SidebarView, CenterPane
                        |
                        |  read / write
                        v
 Store        VaultStore (single writer)      MeetingRecorder (owned by RootView,
                        ^                        its own state machine)
                        |  read / write               |  starts
                        |                             v
 Vault        VaultReader, VaultWriter,     Audio ->  AudioCaptureSession
              FrontmatterCodec,                    -> speech-swift ASR
              TranscriptCodec, ImageSquarer        -> mlx-swift-lm LLM (cleanup + summary)
                        |                                    |
                        v                                    |  writes transcript + summary
              people/organizations/projects/                 |
              meetings/*.md + assets/*.png    <---------------
              (the vault folder on disk)         (back into VaultStore, above)
```

Four layers, each with one job:

- **Views** render whatever `VaultStore` currently holds and route every mutation back
  through it. No view talks to the filesystem directly.
- **Store** (`VaultStore`, `MeetingRecorder`) is the only thing that reads or writes the
  vault. `VaultStore` is a single `@Observable @MainActor` object; `MeetingRecorder` is a
  separate object for the same reason a database connection pool doesn't live inside a web
  framework's router: a recording is a long-running process with its own state machine, not
  a single atomic call.
- **Vault** (`VaultReader`/`VaultWriter`/codecs) is where markdown-with-frontmatter becomes
  Swift values and back, and where the atomic-write guarantee lives.
- **Audio → Transcription → Summarization** is a pipeline that only exists while a meeting is
  being recorded or just finished recording; it hands its output to `VaultStore` like anything
  else and otherwise has no presence in the running app.

## Model layer

`Sources/MaillageCore/Model/`

Every entity conforms to `Entity: Identifiable, Hashable, Sendable`: an `id: EntityID`
(a plain `String`, always equal to the vault filename stem), a `kind: EntityKind`, a
`displayName`, and a `body: String` (the free markdown below the YAML frontmatter). `EntityKind`
is `.person | .organization | .project | .meeting`, and carries per-kind UI facts: directory
name, plural label, SF Symbol fallback, and whether the kind supports a logo (meetings don't).
`AnyEntity` type-erases the four concrete types into one enum so the sidebar, command palette,
and graphs can hold a mixed list.

Cross-entity links are never nested objects. They're always a `Wikilink`, a single-field
wrapper around an `EntityID` that encodes as `"[[id]]"` and decodes tolerantly (accepts a bare
id, and strips Obsidian's `[[id|display]]` / `[[id#heading]]` suffixes down to just the target).
`Wikilink.slugify` is the one place a display name becomes an id: fold diacritics and case,
replace non-alphanumerics with single dashes, trim the ends.

```
STORED (written to a file)
  Person   --organization------------------------> Organization
  Person   --projects: ProjectMembership----------> Project
  Person   --relations: Relation, one-way---------> Person
  Project  --organization------------------------> Organization
  Meeting  --organization, project, attendees------> Organization, Project, Person
             (read-only: Meeting reads these, nothing points back at a Meeting)

DERIVED (computed in memory at load time, never persisted)
  Organization <-- members -------- scans every Person.organization
  Project      <-- participants --- scans every Person.projects
  Person       <-- backlinks ------ inverts every Person.relations
```

The stored rows are what's actually written to a file; the derived rows are computed in
memory at load time and never persisted. This is deliberate throughout: **membership and
relations live
on exactly one side of the link**, and the other side's view of them is always derived:
`VaultStore.rebuildBacklinks()` inverts `Relation`s into `Backlink`s, `members(ofOrganization:)`
and `participants(ofProject:)` scan every person rather than reading a stored roster. Nothing
about a meeting is ever pointed _at_: a meeting reads a person/org/project's identity, but
deleting or renaming one of those has to reach into every meeting file to fix it up (see
`VaultWriter.rename` below), because there's no inverse index to walk.

The four concrete types:

| Type           | Frontmatter fields                                                                                                | Notable quirks                                                                                                                                                                                                                                                                                                             |
| -------------- | ----------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Person`       | `id, type, firstname, lastname, email, role, placeholder, descriptor, organization, projects, relations, created` | `organization` is singular; a retired plural `organizations` key still decodes (first element wins) so old vaults load, but only the singular form is ever written back; a file migrates forward the next time it's saved. `displayName` falls back to `descriptor` (for an unresolved placeholder), then to the raw `id`. |
| `Organization` | `id, type, name, domain, created`                                                                                 | No membership field; see the derived-backlinks note above.                                                                                                                                                                                                                                                                 |
| `Project`      | `id, type, name, status, organization, created`                                                                   | `status` is `.active \| .paused \| .done`. Same singular/legacy-plural `organization` quirk as `Person`. No roster field; derived the same way.                                                                                                                                                                            |
| `Meeting`      | `id, type, title, date, duration, language, organization, project, attendees, created`                            | `attendees` is a flat, hand-maintained list; there is no speaker identification anywhere in the app (see below). `duration` and `language` are `nil` until transcription finishes. `body` holds a `## Summary` block (opaque LLM markdown) followed by a `## Transcript` block (owned by `TranscriptCodec`).               |

`ProjectMembership` (`to: Wikilink`, `role: String?`) has hand-written `Codable` that accepts
either a bare `"[[project-id]]"` or a `{to, role}` mapping, and collapses back to the bare form
on encode whenever `role` is empty, so an untouched membership stays byte-identical across
saves, and adding a role is the only thing that ever expands a file's YAML. `Relation`
(`to: Wikilink`, `label: String`) is stored only on the source person; `Backlink` is its
purely-in-memory inverse (not `Codable`; it's never written anywhere).

`CalendarDay` (`year, month, day`) exists instead of `Date` because Yams serializes a bare
`Date` as a UTC timestamp, which shifts the calendar day backward for anyone east of UTC.
Decode tries a quoted string first, falls back to reinterpreting a bare-YAML `Date` in UTC to
recover the intended day; encode always writes `'yyyy-MM-dd'`.

**A `Speaker`/`Voiceprint` model existed for one commit and was fully removed.** All that
survives is backward-compatibility parsing in `TranscriptCodec`: a transcript line written
while the app briefly diarized speakers may carry a stale `#M2` or `#M2:person-id` tag after
its timestamp, and `parseLine` recognizes and discards it. Nothing parses it into a value, and
nothing ever writes one back out. `TranscriptSegment` (the in-memory unit both the ASR pipeline
and `TranscriptCodec` deal in) has only `offsetSeconds` and `text`, by design.

## Vault layer

`Sources/MaillageCore/Vault/`

`VaultLocation` wraps a single root folder (default `~/Documents/Maillage`) and computes every
path anyone else needs: `people|organizations|projects|meetings/<id>.md`,
`assets/<kind>/<id>.png` (partitioned by kind, since an id is only unique _within_ a kind),
`.maillage/recordings/<meeting-id>/` (created only once a recording starts, cleaned up once its
transcript is written), and `.maillage/prompts/<name>.md` (seeded lazily on first use, not at
vault creation).

`FrontmatterCodec` is the whole `---\nyaml\n---\nbody` format in one place: `split` finds the
fences and returns `(yaml, body)` such that `body` round-trips byte-for-byte; `decode` runs
`Yams.YAMLDecoder` over the yaml half; `encode` runs `Yams.YAMLEncoder` with `sortKeys = false`
(preserves each type's declared key order, so saves diff cleanly) and `width = -1` (stops
libyaml line-wrapping a long list of wikilinks mid-array).

`TranscriptCodec` does the same job one level down, for the `## Transcript` section of a
`Meeting.body`: `split` treats everything above the heading as an opaque `preamble` (the
LLM-written summary) and parses everything below line-by-line into `[TranscriptSegment]`;
`join` rebuilds it, omitting the heading entirely when there are no segments yet. Its
`formatTimestamp`/`parseTimestamp` (`MM:SS` below an hour, `H:MM:SS` at or above) are shared
with `Meeting.formattedDuration`, so the two can never disagree on units.

`VaultReader.load()` walks each `EntityKind`'s directory, decodes every file, and, in the
identity rule made concrete, **overwrites whatever `id:` the frontmatter claims with the
actual filename stem**. A parse failure becomes a `VaultLoadIssue` (surfaced in the sidebar)
rather than aborting the whole load; one bad file never takes down the vault.

`VaultWriter` is where every mutation lands, and everything it writes (a `.md` entity file, a
`.png` logo, a `.maillage/prompts/*.md` template) goes through the same primitive,
`writeAtomically(_:to:)`: write the bytes to a same-directory temp file
(`.<filename>.tmp-<uuid>`) via `Data.write(options: .atomic)`, then swap it into place with
`FileManager.replaceItemAt` (or a plain `moveItem` if nothing exists at the destination yet).
A crash or force-quit mid-save can therefore never leave a half-written file: the destination
is always either wholly the old version or wholly the new one.

`VaultWriter.rename(kind:from:to:)` is the most involved single method in the vault layer,
because renaming is the one operation that has to repair every inbound reference, not just the
renamed file itself:

1. Reject if `newID` already exists or `oldID` doesn't.
2. Re-encode the entity under its new id, write it, delete the old file.
3. Move the logo file across (clobbering any stray debris already at the destination).
4. Walk every person and rewrite matching `relations[].to.id` / `organization?.id` /
   `projects[].to.id`, whichever applies to the renamed kind.
5. `repointMeetings` walks every meeting and rewrites `attendees[].id` / `organization?.id` /
   `project?.id` the same way (split into its own method to stay under the project's
   cyclomatic-complexity budget). Meetings need no _inbound_ repointing of their own, since
   nothing points at a meeting.

`ImageSquarer` normalizes every logo to a 512×512 PNG regardless of source format or aspect
ratio: load via `NSImage(contentsOf:)`, draw into a 512×512 `NSBitmapImageRep` with an explicit
`.size` (avoiding an implicit Retina scale-factor mismatch), **center-crop and scale in one
`draw` call** rather than two passes, so a wide wordmark loses its ends but nothing is ever
double-resampled. `NSImage`/ImageIO alone cover PNG/JPEG/HEIC/WebP/AVIF/TIFF/GIF/BMP/ICO/SVG;
no third-party image library is in the dependency table for a reason.

## Store layer

`Sources/MaillageCore/Store/`

`VaultStore` is a `@MainActor @Observable` object and the only thing in the app that calls
`VaultReader`/`VaultWriter`. Its published state is deliberately small: `snapshot`
(the four `[EntityID: T]` dictionaries `VaultReader` produced), `backlinkIndex` and `logoIDs`
(both derived, rebuilt from `snapshot` and the `assets/` folder respectively, never stored on
disk), and `lastError` for UI display. A private `logoImages` cache holds decoded `NSImage`s
but is deliberately kept _outside_ `@Observable` storage: filling it during a view's render
body would otherwise risk a SwiftUI re-render loop; views instead watch `logoIDs`, which only
changes when a logo is actually added or removed.

Every read the views do goes through a small, purely-derived query surface:
`allPeople/allOrganizations/allProjects/allMeetings`, `members(ofOrganization:)`,
`participants(ofProject:)` (roster + role together, what `ProjectRosterView` reads directly),
`peopleGroupedByOrganization()` (feeds the bubbles graph, unaffiliated people bucketed last),
`meetings(withPerson:/inOrganization:/onProject:)`, and `usedRelationLabels`/`usedProjectRoles`
(vocabulary for autocomplete, with no config file: just "whatever's already in the vault").

Every write goes through the same shape: build/mutate a value, call `writer.write(_:)`, store
the result back into the matching `snapshot` dictionary, `rebuildBacklinks()`. The one method
worth calling out specifically is `setParticipants(ofProject:to:)`, because it's a diff, not a
replace: given the _entire_ intended roster, it adds a `ProjectMembership` for anyone new,
updates a role in place only if it actually changed, removes the membership for anyone dropped,
and only the people whose entry actually changed get written to disk. `resolvePlaceholder`
composes two of these primitives: it fills in a placeholder's real identity, then (if the
resulting display name produces a different slug than the `_`-prefixed placeholder id) calls
`renameEntity`, so "meeting the head of AA" ends with one coherent file move, not a stale
underscore-prefixed filename sitting next to a real name.

`MeetingRecorder` is intentionally its own `@Observable` object, owned by `RootView` (not by
`VaultStore`), because a recording outlives whatever sheet opened it and has a real state
machine `VaultStore`'s call-and-return methods don't need:

```
             start()              stop()             transcript written        summary written
[idle] ─────────────────► [recording] ─────────► [transcribing] ─────────────► [summarising] ─────────► [done]
   │                                                     │
   │ capture failed to start                             │ both tracks failed
   └─────────────────────────────────────────────────────┴───────────────────► [failed(message)]
```

It never talks to `VaultReader`/`VaultWriter` directly: every state change is a
`store.createMeeting`/`store.update(meeting)` call, same as any other part of the app.

## Views layer

`Sources/MaillageCore/Views/`

`RootView` hosts a `NavigationSplitView`: `SidebarView` on one side, `CenterPane` on the other.
There's no third "detail" column. An earlier version had one, purely duplicating the subject's
name beside the graph, so that metadata moved into the center pane's own collapsible header
instead. `CenterPane` picks its content from what's selected, because each selection is a
genuinely different question:

| Selection       | View                      | Because                                             |
| --------------- | ------------------------- | --------------------------------------------------- |
| Nothing         | `OrganizationBubblesView` | "How is the whole network organized by employer?"   |
| An organization | `OrganizationBoardView`   | "What is this company working on, and who's on it?" |
| A person        | `EgoGraphView`            | "Who does this person relate to?"                   |
| A project       | `ProjectRosterView`       | "Who's staffed on this, and in what role?"          |
| A meeting       | `MeetingView`             | "What was said, and what was decided?"              |

The two graphs (bubbles, ego) and the two lists (board, roster) are laid out, never simulated:
a force-directed layout settles somewhere slightly different on every launch, and "Acme is the
big circle in the middle" has to stay true between launches to be worth reading. `MeetingView`
is the odd one out, scrolling a plain top-to-bottom column, since a conversation has no layout
to preserve beyond the order things were said in.

### Layout algorithms

`GraphGeometry.swift` holds primitives shared by both graphs: `ringRadius(in:horizontal:
vertical:floor:)` computes how large a ring can be in a given pane size, treating the margins
reserved for labels as caps (`min(desired, dimension * 0.18)`) rather than fixed reserves, so a
narrow window shrinks the margins before it shrinks the ring below `floor`. `onCircle(center:
radius:angle:)` places a point with angle 0 straight up and increasing clockwise, so labels read
around the ring the way numbers read around a clock face. `trimmed(from:to:gap:)` shortens an
edge's endpoints by each node's `radius + gap` so lines touch the rim rather than vanishing
under the node. `arrowhead(at:approaching:)` builds its triangle from the _curve's_ tangent at
the tip, not the straight chord between endpoints, so an arrowhead on a bowed edge actually
points along the curve.

**`BubblePacking`** (`OrganizationBubblesView.swift`) turns `peopleGroupedByOrganization()`
into circle positions:

1. Each group's radius is `min(minRadius + 26·√(headcount − 1), maxRadius)`
   (`minRadius = 44`, `maxRadius = 150`). Square-root growth ties _area_, not radius, to
   headcount; doubling the radius would otherwise imply 4× the headcount.
2. Groups are sorted biggest-first (ties broken by name), with the "no organization" bucket
   always placed last regardless of size, so the single biggest circle claims the center.
3. Each subsequent circle is placed by a **deterministic spiral sweep**: starting at a distance
   just clearing the first-placed circle, sweep 90 angles around it; if none of them clear every
   already-placed circle by `radius + other.radius + gap`, step the distance out by 3pt and
   sweep again, up to the loosest possible packing (all circles in a line). No physics, no
   relaxation, no randomness: identical input always produces an identical layout, which is
   the whole point.
4. The finished cluster of circles is fit to the pane: compute its bounding box, scale by
   `min(availableWidth/boxWidth, availableHeight/boxHeight, 1.35)` (capped so a vault with one
   company doesn't balloon to fill the window), and center it.

**`EgoLayout`** (`EgoGraphView.swift`) places one person's direct relations as spokes:

1. The subject sits fixed at the pane's center (`subjectRadius = 30`); the ring radius comes
   from the same `ringRadius` helper (`horizontal = 140, vertical = 84, floor = 90`).
2. Every neighbour reachable by _any_ relation (inbound or outbound) is deduped to one node,
   then sorted by employer-cluster position, then name, then id, so colleagues cluster
   together and the order never changes between launches.
3. Nodes are placed evenly around the ring at `angle = 2π·i/count` (`neighbourRadius = 24`).
4. Where more than one relation connects the same pair (a mutual relation, or several labeled
   relations between the same two people), each edge's curve is bowed apart from its siblings:
   `bow = pairSpread · (ordinal − (count−1)/2) · 2` (`pairSpread = 0.16`), and the control point
   for the curve is the midpoint offset perpendicular to the straight line by `bow ×
lineLength`. Each edge's label sits at half that same offset, so it reads near its curve
   without sitting directly on top of it.

### Design system

`Design/Theme.swift` is a namespace of tokens ported from Obsidian's own CSS variables. No
view is allowed to write a literal color, radius, spacing, or font size. Colors resolve via
`adaptive(dark:light:)`, an `NSColor` dynamic provider, so light/dark never branches at the call
site. Each `EntityKind` gets a fixed hue (person purple, organization blue, project amber,
meeting green, chosen as the one hue free of the other three); a separate seven-color
`clusterPalette` (used only to mean "which employer" inside the two graphs) deliberately
excludes purple, since a cluster that looked the same as the selection accent would read as a
lie.

`Design/Components/` holds the reusable primitives, one file per primitive, two of which encode
real gotchas worth knowing before touching a view:

- **`clickableCursor()`** exists because AppKit only swaps the pointer over a view with a
  tracking area, and `.buttonStyle(.plain)` installs none: every plain button in the app would
  otherwise show a plain arrow. It's applied by every clickable control in `Design/Components/`
  by construction, and explicitly passed `false` on a control that's only _sometimes_
  clickable (a disabled button, an action-less `Pill`), since a hand cursor over a dead control
  promises a click that does nothing.
- **Modifier ordering around `.position(...)`**: `.position()` returns a view sized to its
  _entire parent_, drawing its child at one point inside that full-size view. Attaching
  `.onHover`/`.onTapGesture`/`.contentShape` _after_ `.position()` therefore claims the whole
  pane, not just the visual node, and because the last view in a `ZStack` wins that claim,
  every node except the one drawn last would go dead. Both graphs attach every interactive
  modifier _before_ `.position()` for exactly this reason.

`EntityAvatar` is the one component standing for an entity everywhere: a stored logo if one
exists, else a hollow outline for an unresolved placeholder, else the kind's SF Symbol on a
disc in the kind's hue. `EntityLink` (avatar + name, underlined on hover) is what a `Pill` used
to be for a person before logos existed. `Pill` itself is now reserved for things that aren't
entities: relation labels, and removable tokens in the editors.

## Meeting recording & the MLX pipeline

`Sources/MaillageCore/Audio/`, plus the ASR/LLM code alongside `Store/MeetingRecorder.swift`.

This is the newest and least externally documented part of the app, so it gets the most detail
here. The short version: **capture is real-time, transcription and summarization are batch**:
nothing about turning audio into a transcript happens live, despite the live-sample plumbing
described below existing in the capture layer.

### Capture

Two independent recorders converge on the same format (16kHz mono 16-bit PCM, via
`PCMConverter`) and are coordinated by `AudioCaptureSession`:

- **`SystemAudioTap`** wraps a Core Audio process tap: `CATapDescription
(monoGlobalTapButExcludeProcesses:)` excludes maillage's own process (resolved via
  `kAudioHardwarePropertyTranslatePIDToProcessObject`) so the app never records its own output,
  wrapped in a private aggregate device and read via an `AudioDeviceCreateIOProcIDWithBlock`
  callback on Core Audio's real-time thread.
- **`MicrophoneRecorder`** is the ordinary half: `AVAudioEngine.inputNode.installTap(onBus:)`.
- **`AudioCaptureSession.start(microphoneURL:systemAudioURL:)`** starts system audio _first_:
  the tap/aggregate-device setup is measurably slower to spin up than `AVAudioEngine.start()`,
  so starting the slow one first keeps the two tracks' true start times close together. If
  either half fails, the other is torn back down, so a recording never silently captures only
  one track.
- Both recorders also feed an `AsyncStream<[Float]>` of raw samples, consumed today only by
  `RecordingIndicatorPanel`'s live spectrogram HUD, a floating, non-activating `NSPanel` so the
  "is it actually capturing" indicator stays visible even when maillage isn't the frontmost
  window. This plumbing was originally built for a live streaming-transcription design that was
  later reverted (see History below); it survives only because the spectrogram still needs a
  live feed, and transcription itself no longer consumes it.

Audio lands at `.maillage/recordings/<meeting-id>/{mic,system}.wav` and is deleted as soon as
its transcript is safely written (see step 5 below); a crash between those two moments is
caught on the next app launch by `VaultStore.sweepOrphanedRecordings()`, which deletes any
leftover recording directory whose meeting already has a non-empty transcript.

### Transcription: speech-swift (Qwen3-ASR + Silero VAD)

`speech-swift`'s `StreamingASR` (Qwen3-ASR, 0.6B parameters, 4-bit MLX, guided by Silero VAD)
runs **once per finished WAV file, after Stop**, not live, despite the API's name. Silero VAD
walks the whole file first; only voiced spans reach the ASR model, and any continuous voiced
span longer than 10 seconds is force-split. Language is passed as `nil` on every call, which
makes Qwen3-ASR auto-detect language _per VAD-bounded segment_, finer-grained than "detect
once for the whole meeting," and the mechanism this pipeline actually relies on for
code-switching support. There is no confidence score to gate hallucinated output on (the
model's own `TranscriptionResult.confidence` is always `0.0`), so the VAD gate is the only
defense against no-speech hallucination. The source code itself flags this as unverified
against real recorded audio, not assumed safe. Both models are bundled into the app at build
time (`Scripts/fetch-asr-model.sh`, from `aufklarer/Qwen3-ASR-0.6B-MLX-4bit` and
`aufklarer/Silero-VAD-v6.2.1-MLX`), never fetched at runtime.

### Cleanup and summarization: mlx-swift-lm (Qwen2.5-1.5B-Instruct)

Both tracks' transcripts are merged by timestamp (`TranscriptMerger`, stable sort,
mic-before-system on a tie, no speaker labels, just chronological order), then one shared
`Qwen2.5-1.5B-Instruct` model (loaded once via `mlx-swift-lm`, and used strictly sequentially
for the two passes below, since loading it twice would just re-read ~840MB of weights for no
benefit) does two separate jobs:

- **Cleanup** (`LocalLLMTranscriptCleaner`) is map-only over 25-segment windows: each window is
  re-prompted to strip hallucinated/nonsensical fragments while preserving wording and the
  original `(mm:ss) text` line format. A plausibility check rejects a response that lost more
  than half its segments or produced a timestamp past the window's own last one, treating that
  as "the model did something else entirely," and falls back to the **original, uncleaned**
  segments for that window. Cleanup can degrade; it can never destroy data.
- **Summarization** (`LocalLLMSummarizer`) is true map-reduce over 50-segment windows: each
  window gets its own partial markdown summary, and if there's more than one window, a second
  LLM call reduces the partials into one final summary. Unlike the original design's
  `@Generable struct MeetingSummary` (a `FoundationModels` structured-output type), this model
  just writes markdown text directly with no schema validation at all. MLX has no equivalent
  guarantee, and the app leans on `MarkdownUI` to render whatever comes back rather than parsing
  it into fields. A window that throws is dropped; only every window failing surfaces as an
  error, since there's no sensible "unchanged" fallback for a summary the way there is for
  cleanup.

Both prompts (`.maillage/prompts/cleanup.md`, `.maillage/prompts/summary.md`) are ordinary,
vault-editable markdown files, seeded from a built-in default the first time a meeting needs
one, so tuning either prompt is a text edit, not a code change. `swift-transformers`'s actual
role in all of this is narrow: `AutoTokenizer.from(modelFolder:)` loads the tokenizer straight
off the bundled model directory, entirely locally. Nothing about it talks to the Hugging Face
Hub despite the loader macro's name.

### End-to-end flow

```
 1. User            -> MeetingRecorder      : start(title, org, project, attendees)
 2. MeetingRecorder -> VaultStore           : createMeeting
 3. MeetingRecorder -> AudioCaptureSession  : start(mic, systemAudio)
                                               state = recording

 4. User            -> MeetingRecorder      : stop()
 5. MeetingRecorder -> AudioCaptureSession  : stop()  ->  elapsed duration
 6. MeetingRecorder -> VaultStore           : update(meeting.duration)
                                               state = transcribing (stop() returns
                                               immediately; the rest runs in the background)

 7. MeetingRecorder -> speech-swift ASR     : transcribe(mic.wav)      \  concurrent
    MeetingRecorder -> speech-swift ASR     : transcribe(system.wav)   /
                                            <- segments, from one or both tracks
                                               (only both tracks failing is fatal;
                                                one failing degrades gracefully)

 8. MeetingRecorder merges segments by timestamp
 9. MeetingRecorder detects language (NLLanguageRecognizer, on the merged text)
10. MeetingRecorder -> mlx-swift-lm         : clean(merged, language)
                                            <- cleaned segments (or the original,
                                               uncleaned segments, on failure)
11. MeetingRecorder -> VaultStore           : write transcript into meeting.body
12. MeetingRecorder deletes the recording directory
                                               state = summarising

13. MeetingRecorder -> mlx-swift-lm         : summarize(merged, language)
                                            <- markdown summary
14. MeetingRecorder -> VaultStore           : write summary preamble into meeting.body
                                               state = done
```

Language detection runs on the merged **text**, once, after transcription: a departure from
detecting language on raw audio before decoding, made possible because per-segment detection
already happened inside the ASR step above.

### History and open questions

The pipeline arrived at its current shape after real churn, not by design from day one:
WhisperKit + on-device `FoundationModels` summarization → add FluidAudio alongside WhisperKit →
add a `Voiceprint` model and speaker tags → tap live PCM off both tracks (building toward a
live pipeline) → fully replace WhisperKit with **live** FluidAudio transcription, diarization,
and speaker resolution → and finally, in the commit at `HEAD`, rip all of that back out in
favor of the **batch** `speech-swift` + `mlx-swift-lm` pipeline described above. No FluidAudio,
WhisperKit, `Voiceprint`, or diarization code remains anywhere in the current source tree.

Things worth a contributor's attention before relying on this pipeline further:

- **No vocabulary or name-biasing mechanism exists.** The original design's plan to bias the
  decoder with attendee/org/project names from the vault (so "Marie Dupont" transcribes
  correctly) didn't survive the switch to Qwen3-ASR. Proper-noun accuracy depends entirely on
  the raw model today.
- **Hallucination and code-switching behavior are self-flagged as unverified** in
  `LocalASRTranscriber`'s own comments: real-audio testing, not just unit tests, is still
  needed to confirm both.
- **`Package.swift`'s `.macOS(.v26)` floor is now an open question.** It was raised for
  `FoundationModels`, which has since been removed entirely; whether anything else in the app
  still needs macOS 26 has not been investigated.
- **`TranscriptChunker.swift`'s doc comment references a `TokenTimingGrouper` type that no
  longer exists** anywhere in the source tree, a leftover from the WhisperKit era that wasn't
  cleaned up when the ASR backend changed.
- **No speaker identification exists anywhere.** This was deliberate, not an oversight: it's
  the ending state of the arc above. `Meeting.attendees` is a flat, hand-maintained list;
  `TranscriptSegment` carries no speaker field; the transcript view groups lines into
  paragraphs purely by silence gap. Attributing a line to "mic track" vs. "system track" was
  considered and rejected as a guess dressed up as a fact.

## Where to go next

- [CLAUDE.md](CLAUDE.md): build systems, CI pipeline, releasing, the vault file format, and
  the invariant rules the test suite enforces.
- [docs/superpowers/specs/2026-08-13-meeting-recording-design.md](docs/superpowers/specs/2026-08-13-meeting-recording-design.md)
  is the original meeting-recording design. Treat it as **historical**: the shipped pipeline
  diverged from it on several major points (WhisperKit → speech-swift, `FoundationModels` →
  mlx-swift-lm, and the speaker-identification feature it assumed never shipped at all); see
  History and open questions above.
