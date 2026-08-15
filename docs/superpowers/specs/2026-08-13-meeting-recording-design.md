# Meeting recording, multilingual local transcription, and meeting history

## Context

maillage knows *who* you know. It doesn't know *when you last spoke to them*, which is what a
personal CRM is actually for. The goal: record a meeting (your mic plus whatever Teams is playing),
turn it into a transcript and a summary, attach it to the people who were there, and be able to open
a person and see every meeting you've had with them.

Three constraints shape every choice below:

- **Everything runs on the machine.** No audio, no transcript, no summary crosses the network. Model
  *weights* are fetched from Hugging Face at **build time** by `Scripts/fetch-whisper-model.sh` and
  embedded in the app bundle — nothing is fetched, and no network is needed, at runtime. Content
  never crosses the network, on any run.
- **The recording is deleted** as soon as both tracks transcribe. The transcript is the artefact.
- **Code-switching is a first-class requirement, not a nicety.** You speak French with English
  technical vocabulary in the same sentence. A transcriber that forces one language per meeting is
  the wrong tool, and that single fact decides the ASR choice.

**No speaker detection.** No diarization, no voiceprints. You add attendees by hand while the meeting
is happening. This also removes all GDPR Art. 9 exposure — without a voiceprint there is no biometric
data anywhere in the system. The one remaining legal obligation is that participants must know they
are being recorded (in France that is criminal law, not only GDPR), which is why a visible recording
indicator is a requirement rather than a polish item.

## Decisions taken

| Decision | Choice |
|---|---|
| Transcription | **WhisperKit** (MIT, argmax inc.), CoreML, multilingual `openai_whisper-small` (216MB, quantized) — the smallest variant with usable multilingual/code-switching accuracy, embedded in the app at build time rather than downloaded. One model, shared vocabulary — English terms inside French sentences stay English |
| macOS floor | **Raised 14 → 26**, for `FoundationModels` only. Gives a free on-device summary LLM instead of a second multi-GB download |
| Meeting storage | A **4th `EntityKind`**, `meetings/<id>.md`, reusing `FrontmatterCodec`, `VaultReader`/`VaultWriter`, the sidebar, the palette, `[[id]]` linking |
| Meeting fields | title, date, duration, language, attendees, organization, project |
| Attendees | Flat `attendees:` list, added live during recording |
| Audio retention | Deleted the moment both tracks transcribe; orphans swept at launch |
| Record entry point | A **Meetings** sidebar section with the same per-section `+`, opening a recording sheet |

## Why two capture files

Mic and system audio are captured to **two separate files**, never mixed. This is not speaker
detection — it is that they are different APIs (`AVAudioEngine` vs. a Core Audio process tap), so
capturing them separately is *less* work than mixing them. Neither track is ever labelled by
speaker, though: that would only be true for a remote call, where the other party's voice can only
physically enter through the system tap. An in-person meeting recorded on one laptop puts everyone's
voice through the mic, so the mic track can hold any number of unidentified people — "You" would be
a guess dressed up as a fact. The transcript stays plain, timestamped text; see
`TranscriptSegment`.

## Architecture

Everything testable lands in `MaillageCore`; the app target stays a thin `@main` shell.

```
Sources/MaillageCore/
├── Model/Meeting.swift            4th entity; TranscriptSegment
├── Vault/TranscriptCodec.swift    strict round-trip for the body's Transcript block
├── Audio/                         AudioCaptureSession, SystemAudioTap,
│                                  MicrophoneRecorder, CapturePermissions
├── Transcription/                 Transcriber (protocol), WhisperTranscriber, LanguageDetector,
│                                  WhisperModelStore, VaultVocabulary, TranscriptMerger
├── Summary/                       MeetingSummarizer (protocol), FoundationModelsSummarizer,
│                                  TranscriptChunker
├── Store/MeetingRecorder.swift    the pipeline state machine
└── Views/RecordingSheet.swift, MeetingView.swift
```

### Capture — `Audio/`

- `SystemAudioTap` confines the ugly C API to one file: `CATapDescription`
  `initMonoGlobalTapButExcludeProcesses:` — excluding our own PID via
  `kAudioHardwarePropertyTranslatePIDToProcessObject`, so the app never records its own output —
  then `AudioHardwareCreateAggregateDevice` with the tap as a sub-tap, then an IOProc into an
  `AVAudioFile`.
- `MicrophoneRecorder` is an `AVAudioEngine` input tap into a second `AVAudioFile`.
- Both write **16 kHz mono PCM**, which is exactly what `WhisperKit.transcribe(audioArray:)` consumes,
  so nothing resamples. It is also ~10× smaller than 48 kHz stereo, for audio that gets deleted.
- `AudioCaptureSession` starts/stops both and publishes elapsed time plus a **level meter per track**.
  The meters are the honest signal that capture is working; a spinner is not. A silent system track
  because the tap was refused is the most likely failure and must be visible while recording, not
  discovered in an empty transcript.
- Files land in `.maillage/recordings/<meeting-id>/{mic,system}.wav` — inside the vault so they
  travel, app-private so they read as transient.

### Transcription — `Transcription/`

```swift
protocol Transcriber {
    func transcribe(fileAt: URL, language: Locale?, vocabulary: [String])
        async throws -> [TranscriptSegment]
}
```

`WhisperTranscriber` implements it over WhisperKit:

- `DecodingOptions.language` **forced from a one-shot language-ID pass**, not left `nil` for the
  real decode — see constraint 2 below for why auto-detect-and-hold, not per-chunk auto-detect.
- `wordTimestamps: true` for per-segment timing, `chunkingStrategy: .vad` for long recordings.
- **`promptTokens` carries the vocabulary prompt** — the biasing lever that makes "Marie Dupont" and
  "Acme" come out spelled right rather than phonetically. Not `prefixTokens`, which forces the *start
  of the output* and exists for streaming continuity.

#### The vocabulary prompt

This is the mechanism the whole multilingual requirement rests on, and it has three hard constraints
that dictate its shape. WhisperKit builds the decoder input as
`[startOfPreviousToken] + trimmedPromptTokens + prefillTokens`, truncating the prompt to
`(Constants.maxTokenContext / 2) - 1` — **223 tokens** for Whisper's 448-token context. Read it from
the constant, never hardcode it.

Nothing here is about money — the model runs locally and costs nothing to invoke. 223 tokens is a
*capacity* fixed by the model architecture, and the reason it drives the design is that **WhisperKit
truncates silently**: pass 500 names and it trims to the limit and transcribes happily, with no error
and no sign that everything past the cut had no effect.

**Constraint 1: ~223 tokens is small.** Roughly 150 English words, and far fewer for French proper
nouns, which tokenize badly. The prompt is therefore **meeting-scoped, not vault-scoped** — priming
on every name in the vault would overflow the limit and dilute the names that matter. Since attendees
are added live, by transcription time we know exactly who to prime for. Because the trim is silent, the
order it happens in is the whole safeguard — drop jargon before dropping a colleague's name:

1. attendee display names
2. the meeting's organization and project names
3. terms from `.maillage/vocabulary.txt`, until the limit is reached

**Constraint 2: a bare word list can flip the output language.** Whisper treats the prompt as
*previous text*, so an English comma-list ahead of French speech pulls the decoder toward English or
into outright translation — the exact failure this feature exists to avoid. The prompt is therefore
rendered as a **natural sentence in the meeting's base language with the English terms inline**, which
also demonstrates the code-switched register we want:

> `Réunion avec Marie Dupont et Jean Martin chez Acme Corp, projet maillage. On parle de feature flag,`
> `de canary deploy et de pull request.`

Prose conditions better than a list and is less likely to be echoed verbatim. Carrier templates are
per base language (fr, en), with en as the fallback.

`language` is not user-picked and not left to auto-detect on every chunk either. `LanguageDetector`
runs `WhisperKit.detectLanguage` **once**, on the mic track's first voiced window (skipping leading
silence/noise — language-ID on pure silence is unreliable and known to default to English), falling
back to the system track's first voiced window if the mic has no detectable speech at all — a
meeting recorded while mostly listening (a call you mostly listen to, or just testing transcription
by playing a video with the mic silent) otherwise hands the detector nothing but room tone, and a
language guessed from noise gets forced onto real speech on the other track for the whole meeting.
That result is **held and forced** for every chunk of both tracks for the rest of
the meeting, so the `<|fr|>` prefill token keeps anchoring the language after the prompt exactly as
before — the anchor is just fed by detection now, not a picker. Per-chunk redetection was considered
and rejected: everything downstream assumes one language per meeting (the frontmatter's single
`language:` key, the summary's "dominant language"), and redetecting per chunk reopens this exact
constraint's flip risk at finer grain — a jargon-heavy chunk misdetecting on its own, not just a
genuine language switch, which this feature was never scoped to track (see "Explicitly out of
scope").

**Constraint 3: Whisper echoes prompts** into the transcript, especially on the first window and over
silence. `PromptEchoFilter` strips a leading segment that fuzzy-matches the prompt. This is a real
observed behaviour, not a hypothetical — it needs a filter, not optimism.

```swift
struct VocabularyPrompt {
    static func build(
        meeting: Meeting,
        snapshot: VaultSnapshot,
        customTerms: [String],
        tokenLimit: Int,
        countTokens: (String) -> Int
    ) -> String
}
```

Token counting means this cannot be a pure function of the snapshot alone; injecting `countTokens`
keeps it unit-testable with a fake counter and uses WhisperKit's real tokenizer in production. Source
material — person display names, organization and project names, `usedProjectRoles`,
`usedRelationLabels` — is all already derived in `VaultStore`.

**To verify in phase 4:** `promptTokens` lives on `DecodingOptions`, and `AudioChunker.chunkAll` passes
the same options to every chunk, so the prompt *should* be reapplied per window rather than only the
first. That is inferred from the call structure, not stated in the docs — confirm it empirically on a
recording longer than one chunk, because if it only primes window one, a 30-minute meeting is biased
for its first 30 seconds and the feature is largely cosmetic.

**Also to verify in phase 4:** confirmed empirically that a mic track with no detectable speech at
all (a meeting recorded while mostly listening) falls back to the system track rather than guessing
from noise — `LanguageDetector` now does this. Still open: whether a mic track with a *little*
unrepresentative speech (a few words of cross-talk, then mostly silence) picks a worse language than
falling back would have; that's a real judgment call about "enough" speech to trust, not something
the fallback's simple has-any-voiced-second check resolves.

`WhisperModelStore` resolves the model bundled inside the running app and loads it. There is no
download-progress UI to build and no partial-download recovery to design: `Scripts/fetch-whisper-model.sh`
fetches the model once at **build time** (cached in `.whisperkit-model-cache/`, never committed —
see the "Fetch WhisperKit Model" build phase in `maillage.xcodeproj`), so at runtime the model is
either present in the signed bundle, in which case loading it cannot meaningfully fail from
anything this type controls, or the bundle itself is broken, which is a build problem, not a
runtime one.

`TranscriptMerger` interleaves the two tracks' segments by start time into one chronological
transcript — no speaker labels, since neither track can be honestly attributed to one person. Pure
and unit-tested.

### The transcript lives in the markdown

The meeting body is **authoritative** — no hidden sidecar. It keeps the app's premise (your data is a
folder of readable markdown) true for meetings, and it means fixing a mis-transcribed term in
Obsidian just works.

```markdown
---
id: 2026-08-13-acme-standup
type: meeting
title: Acme standup
date: '2026-08-13'
duration: 1847
language: fr
organization: "[[acme-corp]]"
project: "[[maillage]]"
attendees:
  - "[[marie-dupont]]"
  - "[[jean-martin]]"
created: '2026-08-13'
---

## Summary

**Ship the importer behind a canary flag.**

### Decisions
- Ship behind a canary flag.

### Actions
- Marie: wire the flag before Friday.

## Transcript

(00:12) On ship le feature flag cette semaine ?
(00:15) Oui, mais il faut wire le canary d'abord.
```

`TranscriptCodec` round-trips the Transcript block, mirroring what `FrontmatterCodec` already does for
the header. The format is generated and strict, so parsing is reliable.

### Summary — `Summary/`

`FoundationModelsSummarizer` uses `LanguageModelSession.respond(to:generating:)` with an `@Generable`
struct — a typed result, not prose to parse:

```swift
@Generable struct MeetingSummary {
    @Guide(description: "One sentence, in the meeting's dominant language") var headline: String
    var keyPoints: [String]
    var decisions: [String]
    var actionItems: [ActionItem]   // owner + what + optional due
}
```

The on-device context window is small and `GenerationError.exceededContextWindowSize` is real, so
summarising is **map-reduce**: `TranscriptChunker` splits segments into fixed-size windows, each
window is summarised, then the summaries are reduced into one. The chunker is pure and
unit-tested; `exceededContextWindowSize` is caught by halving the window and retrying. Guard on
`SystemLanguageModel.availability` and degrade to "transcript, no summary" rather than failing the
meeting — a transcript without a summary is still worth keeping.

### Pipeline — `Store/MeetingRecorder.swift`

A `@MainActor @Observable` coordinator, deliberately **not** part of `VaultStore`: the store mirrors
the vault and should not drive a long-running pipeline.

```
idle → recording → transcribing → summarising → done
                        ↓
                 audio deleted here
```

A launch-time sweep deletes any `.maillage/recordings/` directory whose meeting already has a
transcript. Without it a crash mid-pipeline leaves audio on disk forever and the deletion promise
holds only on the happy path.

### `VaultStore` additions

Following the existing derive-by-scanning pattern (`members(ofOrganization:)`, `rebuildBacklinks`):
`allMeetings`, `createMeeting`, `update(_ meeting:)`, and `meetings(withPerson:)`,
`meetings(inOrganization:)`, `meetings(onProject:)`. Attendance lives on the **meeting**, never copied
onto the person — a person file must not accumulate hundreds of meeting links. `delete` and
`renameEntity` must also sweep and rewrite `attendees:`, `organization:` and `project:` in meetings.

### Views

- `SidebarView` — a 4th Meetings section; `+` opens `RecordingSheet`; red indicator while recording.
- `RecordingSheet` — title, org/project/attendee pickers reusing the editors' existing search-pick
  controls, Start/Stop, elapsed time, level meters, then pipeline progress. No language field: it's
  detected from the audio, not chosen. Attendees stay editable **during** recording.
- `MeetingView` — centre pane for a selected meeting: summary card, attendees as `EntityLink`s,
  transcript. Registered in `CenterPane`'s selection routing.
- `EntityDetails` — a person gains a derived **Meetings** list. This is the payoff of the whole
  feature.
- `EntityKind` gains `supportsLogo` (false for `.meeting`) so `createSkeletonIfNeeded` skips a
  pointless `assets/meetings/` and avatars fall back to the kind glyph.

Existing invariants still bind: `Theme` tokens only, `clickableCursor()` on every control,
`CalendarDay` never `Date`, atomic writes through `VaultStore`, no `keyboardShortcut` anywhere.

## Plan

**Phase 0 — commit the spec.** Write this design to
`docs/superpowers/specs/2026-08-13-meeting-recording-design.md` and commit.

**Phase 1 — platform bump.** macOS 14 → 26 in `Package.swift` *and* `MACOSX_DEPLOYMENT_TARGET` in
`project.pbxproj` — both, or the two build paths compile against different SDKs. Add
`NSMicrophoneUsageDescription` to `App/Info.plist` (`NSAudioCaptureUsageDescription` is already
there). Extend `Scripts/check-build-parity.sh` to assert the deployment targets match. Update
CLAUDE.md's stack table.

**Phase 2 — the meeting entity, no audio.** `Meeting`, `EntityKind.meeting`, `TranscriptCodec`,
`VaultStore` additions, `MeetingView`, the sidebar section, the per-person history list. Seed a
meeting file by hand to drive the UI. Ends with a runnable app that browses meetings — worth having on
its own, and it gives the next two phases somewhere to write.

**Phase 3 — capture only.** `Audio/`, `RecordingSheet` with live attendees, permission prompts, level
meters. Stops at two WAVs on disk and a meeting file with no transcript. Verifiable in isolation,
which matters because the process tap is the single most failure-prone piece here.

**Phase 4 — transcription.** Add WhisperKit to `Package.swift` **and** `project.pbxproj` (versions are
declared twice in this repo; bump them together), and to CLAUDE.md's dependency table with its MIT
licence. `WhisperTranscriber`, `LanguageDetector`, `WhisperModelStore`, `VocabularyPrompt`,
`PromptEchoFilter`, `TranscriptMerger`, audio deletion, the orphan sweep — plus
`Scripts/fetch-whisper-model.sh` and the "Fetch WhisperKit Model" Xcode build phase that embeds the
model at build time, so nothing downloads at runtime.

**Calibrate on a real code-switched recording**, measuring three things separately so a bad result
points at a cause: (a) the vocabulary prompt on vs. off, to confirm it earns its
complexity; (b) whether the prompt reaches windows past the first; (c) whether `LanguageDetector`
correctly identifies the meeting's dominant language across mic-silent, system-silent, and
both-tracks-quiet recordings, since that result gates building the prompt at all.
`openai_whisper-small`
is a fixed, already-decided choice at this point (the smallest variant with usable multilingual
accuracy), not a runtime knob to calibrate against a config default. Ends with the real
feature working.

**Phase 5 — the summary.** `TranscriptChunker`, `FoundationModelsSummarizer`, the summary card.
Isolated by design: if phases 1–4 run long, ship them and do this next.

One PR per phase, each with a conventional title (`feat:` for 2–5, `build:` for 1) so
semantic-release versions it correctly.

## Verification

- `rtk swift test` — the fast path. New suites: `TranscriptCodecTests` (round-trip; `**`, parentheses
  and newlines inside speech; timestamps past one hour), `VocabularyPromptTests` (with a fake token
  counter: attendee names survive a token limit low enough to drop jargon; output is prose in the base
  language, not a word list; a zero-limit case yields no prompt rather than a truncated fragment),
  `PromptEchoFilterTests` (leading echo stripped, a genuine opening line that merely resembles the
  prompt kept), `TranscriptMergerTests` (interleaving, a same-second tie keeping mic before system,
  one empty track), `LanguageDetectorTests` (trims a leading no-speech window before detecting,
  returns `nil` rather than falling back on a track that's silent throughout — the signal the
  mic-then-system fallback relies on — pure logic against WhisperKit's own VAD, the real
  `detectLangauge` call is gated like the suite below), `MeetingFrontmatterTests` (including a
  meeting with no attendees),
  `VaultStoreMeetingTests` (history derivation; deleting a person clears them from `attendees:`;
  renaming rewrites `[[id]]` inside meetings), `TranscriptChunkerTests` (pure, no LLM).
- Audio capture, WhisperKit and the LLM cannot run headlessly on CI. Gate those suites with
  `.enabled(if:)`, following `SeededVaultTests` — **not** `#require`, which fails rather than skips.
- `make check` then `make build` — parity, lint, format, and a real signed `.app`.
- End-to-end in the running app (`open maillage.xcodeproj`, **Maillage** scheme, ⌘R): play a Teams or
  YouTube clip, talk over it in French using English tech terms, add an attendee mid-recording, stop.
  Confirm both level meters moved, the transcript interleaves both tracks chronologically, **the English
  technical terms are spelled as English words**, vault names are spelled correctly, the summary is in
  French, the meeting appears on the attendee's detail pane, and `.maillage/recordings/<id>/` is gone.
- Kill the app deliberately mid-transcription, relaunch, confirm the orphan sweep removed the audio.
  This is the deletion promise; the crash path is the one that needs testing, not the happy path.
- Confirm the summary card appears after a real recording, written in the meeting's dominant
  language, with Decisions/Actions matching what was actually said.
- With Apple Intelligence off in System Settings (or on ineligible hardware), confirm the meeting
  still ends with a full transcript, no summary card, and no error banner — the silent-skip path,
  not the soft-failure banner path.

## Explicitly out of scope

Diarization and speaker identification, voiceprints, editing a transcript in-app, importing existing
audio files, calendar integration, exporting meetings anywhere, and tracking a meeting whose
*dominant* spoken language itself changes mid-recording (a French half followed by an English
half). "Code-switching is first-class" always meant foreign vocabulary inside one base language,
not a meeting hopping between two base languages — the latter would need per-chunk language
detection and a per-chunk vocabulary prompt, and break the single `language:` field everywhere
else in this design already assumes one.
