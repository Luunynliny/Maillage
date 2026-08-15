# Meeting recording v2: live diarized transcription, and live-editable meeting metadata

## Context

[2026-08-13-meeting-recording-design.md](2026-08-13-meeting-recording-design.md) shipped meeting
recording as a batch pipeline: record mic + system audio to two WAV files, then — only after
Stop — run WhisperKit once per file, merge the two transcripts chronologically, and generate an
on-device summary. It also locked title, organization and project the moment recording started,
leaving only attendees live-editable, and it deliberately ruled out diarization for GDPR Article 9
(biometric data) reasons: "No speaker detection. No diarization, no voiceprints... without a
voiceprint there is no biometric data anywhere in the system."

This version reverses both of those decisions, deliberately, not as drift:

1. **Live transcription and live diarization**, replacing the post-hoc batch pass, on
   [FluidAudio](https://github.com/FluidInference/FluidAudio) (Apache 2.0, CoreML models on the
   Apple Neural Engine) instead of WhisperKit. Diarized speaker slots get manually confirmed
   against a Person, and that confirmation trains a persistent per-person voiceprint, so a
   returning contact is recognized in future meetings instead of being "Speaker 2" forever. This
   is a genuine narrowing of the original privacy stance — see "Reversing the no-diarization rule"
   below for why it's still defensible.
2. **Participants, project and organization become live-editable during recording** (today only
   attendees are). This needed almost no new mechanism: `RecordingSheet` already requires only a
   title to start, and the existing "read snapshot, mutate field, `store.update(meeting)`" pattern
   that already makes attendees live-editable is exactly the pattern the rest reuses.

These two are independent (one is an ML/audio pipeline swap, the other a small UI unlock) but ship
together. Basic fields — duration, date, language — stay exactly as read-only/derived as before;
neither piece touches them.

## Model choices

Two decisions came directly out of FluidAudio's own documented model constraints, not a preference:

- **ASR: Nemotron Speech Streaming Multilingual 0.6B**, not Parakeet EOU. It is the only streaming
  (true real-time) ASR FluidAudio offers that supports French alongside English (en/es/fr/it/pt/
  de/zh/ja, `auto` language mode). Code-switching (French with English technical terms) is a hard
  carry-over requirement from the original design, and Parakeet EOU is English-only.
- **Diarizer: Sortformer**, not LS-EEND, despite Sortformer's hard 4-fixed-speaker-slot limit per
  audio track. FluidAudio's own docs are explicit that Sortformer is the stronger choice for
  pre-enrolled/voiceprint-mapped workflows — exactly this feature's use case — while LS-EEND can
  reject enrollment on similar-sounding voices and has no way to lock a specific person into a
  slot. LS-EEND's higher speaker caps only apply to non-meeting domain variants (`.callhome`,
  `.dihard2`); its `.ami` (in-person meeting) variant is capped at 4 too, so it buys no real
  headroom for this app's actual use case while giving up enrollment reliability.

The 4-speaker cap is a hard, non-configurable model limit — a 5th distinct voice on one track is
missed or silently merged into another slot's segments, never given its own label. Rather than
risk silent misattribution, meetings that exceed it get an explicit opt-out (below) that disables
diarization entirely for that meeting, degrading to the exact experience of today's undiarized
transcript, just live instead of batch.

## Reversing the no-diarization rule

The original rule treated "no diarization" and "automatic, silent speaker identification" as the
only two options. This feature builds a third: **human-supervised identification, not automated
biometric surveillance.** A voiceprint is created only the moment someone deliberately confirms or
accepts a suggested "this voice is Marie" — nobody's voice becomes a voiceprint just by being
recorded. Every suggestion stays visible and reversible, never silent: the app can propose a match
above a similarity threshold, but the UI always reads as "the app guessed X, confirm or fix," and a
wrong assignment can be corrected at any time, live or afterward. Voiceprints stay on-device inside
the vault (`assets/people/<id>.voiceprint`, beside that person's logo) — never uploaded or synced.
Deleting a person deletes their voiceprint, so there's no floating biometric record for someone no
longer in the vault. The stored footprint is one embedding vector plus a sample count, not audio —
it is a comparison key, not a recording, and can't reconstruct what someone said or sounded like.

This is a real narrowing from "never build this," made deliberately: without it, a returning
contact is "Speaker 2" in every meeting forever, which works against the one purpose this app
exists for — remembering who you talked to. The remaining exposure is bounded by the points above:
processing stays confined to one person's own device, for their own record-keeping, under their
own continuous manual control.

## On-device only, extended to the new models

FluidAudio's ASR and diarizer models are CoreML bundles fetched once at build time, exactly like
WhisperKit's was: a new `Scripts/fetch-fluidaudio-models.sh` downloads them from their public
Hugging Face repos and rsyncs the cached bundles into the signed app's `Resources/`. FluidAudio
defaults to downloading models from Hugging Face at runtime, which is the opposite of this app's
constraint — so `ModelHub.offlineMode = true` is set once at launch, before anything touches
FluidAudio's loader. With that flag set, any code path that would otherwise reach the network
throws instead of silently fetching, so a missing or renamed bundled model fails loudly at first
use rather than quietly phoning home. No audio, partial transcript, embedding, or voiceprint ever
leaves the device, on any run, for any meeting.

## Decisions taken

| Decision | Choice |
|---|---|
| Transcription/diarization | **FluidAudio** (Apache 2.0), replacing WhisperKit entirely |
| ASR model | Nemotron Speech Streaming Multilingual 0.6B, 2240ms chunk tier |
| Diarizer model | Sortformer, `.fastV2_1` config, 4-speaker-per-track hard limit |
| Speaker identity | Human-confirmed only; persistent per-person voiceprint via EMA update |
| >4-speaker meetings | Explicit opt-out checkbox at Start, disables diarization for that meeting |
| Live metadata editing | Participants, project, organization all live-editable; title still locks at Start |
| Org/project relationship | Organization auto-derives from the selected project, never independently validated |
| Basic fields | Duration, date, language stay exactly as read-only/derived as v1 |

## Part A: live-editable meeting metadata

`RecordingSheet` already gates "Start Recording" on title alone — organization, project and
attendees are already optional at start. The only actual lock today is `.disabled(isRecording)` on
the organization and project pickers; attendees already stay live via
`syncAttendeesWhileRecording`, which reads the meeting from the store snapshot, mutates the field,
and calls `store.update(meeting)`.

The change: remove the two `.disabled(isRecording)` modifiers, and add
`syncOrganizationWhileRecording`/`syncProjectWhileRecording` mirroring that same pattern exactly.
Organization auto-derives from project — picking a project always sets the meeting's organization
to that project's own organization, which can never mismatch by construction (the same partitioning
`VaultStore.projects(inOrganization:)` already provides for `Person`/`Project` elsewhere). The
project picker's options are filtered to the selected organization's projects when one is set, so a
later project pick can't silently overwrite an organization that was set independently. Clearing a
project doesn't retroactively unset the derived organization. Title stays required-to-start and
locked once recording begins, unchanged from v1.

## Part B: live transcription and diarization pipeline

### Data model

`TranscriptSegment` gains an optional `speaker: Speaker?`, where `Speaker { track: AudioTrack,
slot: Int, personID: EntityID? }` — `track` distinguishes mic from system audio (their speaker
populations are unrelated: in-person room voices vs. remote call voices), `slot` is the diarizer's
0-3 fixed index within that track, and `personID` is set only once a human has confirmed the slot.
The persisted transcript line format extends backward-compatibly: `(00:15) text` (today's format,
unchanged, used whenever diarization is off or the meeting predates this feature), `(00:15 #M2)
text` (diarization on, unresolved), `(00:15 #M2:marie-dupont) text` (resolved). Old-format lines
parse identically to before, with `speaker: nil` — no migration needed.

A person's voiceprint follows this app's existing "a logo is a file, not a field" rule: a new
`assets/people/<id>.voiceprint` JSON asset (embedding vector plus a sample count), scanned and
derived by `VaultStore` the same way logos and backlinks already are, never a frontmatter key.
Deleting or renaming a person moves/deletes its voiceprint exactly as it already does for a logo.

### Live pipeline

Two independent per-track pipelines (mic, system), never sharing state: each gets its own
streaming ASR session and its own streaming Sortformer diarizer session, tapped directly off the
same converted 16kHz mono buffer each track already produces just before writing its WAV file.
Finalized ASR segments are aligned to the diarizer's finalized segments by time overlap, held back
briefly (~2s) to absorb the diarizer's inherent look-ahead latency before being promoted into the
live transcript, then written straight through to the vault via `store.update(meeting)` — the same
atomic-write cost as any other live edit in this app, and durable against a mid-meeting crash.
`MeetingView` needs no new observation plumbing: it already re-derives the meeting from the store
on every mutation, so a live-growing transcript just appears, the same way any other live edit
already does.

### Speaker resolution

When a new diarizer slot appears, its running embedding is compared against every enrolled
person's stored voiceprint; a match above threshold is offered as a suggestion, never applied
silently. Confirming (or correcting) a slot's person: relabels every already-shown segment for that
slot, adds the person to the meeting's attendees automatically (one action, not two), and folds the
slot's embedding into that person's stored voiceprint via a fixed-decay exponential moving average
— chosen specifically so a gradual voice change (illness was the example that prompted this) gets
absorbed over time rather than a single bad sample permanently poisoning the match. A slot left
unresolved when the meeting ends isn't lost — it displays as an anonymous "Speaker N" with a
"Who said this?" affordance — but resolving it after the fact only relabels that meeting's
transcript; the recording is already deleted by then, so it can't also train the voiceprint.

### The opt-out

A checkbox at Start ("More than 4 people speaking through one microphone, or on one call?"),
locked once recording begins like title, since it decides what pipeline objects get created.
Checking it skips diarization entirely for that meeting: no diarizer is created, every segment's
`speaker` stays `nil`, attendees stay entirely manual. The resulting transcript is line-for-line
identical in shape to a pre-this-feature meeting — no separate frontmatter flag needed, consistent
with this app's existing derive-don't-store-twice philosophy.

## Out of scope

Automatically re-training a voiceprint from a post-hoc "Speaker N" resolution (the audio is already
gone by then). Cross-device voiceprint sync (voiceprints are vault-local like everything else).
Raising the 4-speaker limit itself (it's a hard model constraint; the opt-out is the answer, not a
workaround). Editing transcript text itself (unchanged from v1's scope).
