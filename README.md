# maillage

A personal CRM for macOS.

People, organizations and projects live as plain markdown files with YAML frontmatter, the
same format Obsidian itself uses, so the data is yours: readable in any text editor,
diffable, versionable with git, and never locked into a proprietary format. Labeled
relationships between people are drawn as a force-directed-looking graph, clustered by
employer, laid out deterministically rather than simulated so the same vault always looks the
same way twice.

## Why

Most CRMs put your network of contacts, your notes about them, and now your meeting
recordings on someone else's server. maillage doesn't. It's built for one person, running
entirely on one Mac, with no account, no server, and no dependency on a network connection to
work.

## Everything runs locally

There's no backend, and no API key to configure. Your data is a folder:
`~/Documents/Maillage` (or wherever you point it), one markdown file per person,
organization, and project. Nothing about the app requires a database, a sync service, or an
account.

Meeting transcription and summarization run entirely on-device, through
[MLX](https://github.com/ml-explore/mlx-swift), Apple's on-device machine learning framework.
Audio is transcribed by a local speech model and summarized by a local language model, both
running on the Mac's own GPU. No audio, no transcript, and no summary is ever sent anywhere,
and nothing in this codebase calls out to a cloud AI provider: no OpenAI, no Anthropic API, no
telemetry endpoint. If a feature needs intelligence, it runs a model that ships inside the
app.

## GDPR-compliant by nature, not by policy

A privacy policy is a promise about what a company does with your data. maillage doesn't need
one: there's no company in the loop, and nowhere for the data to go. Nothing is transmitted to
a third party, so there's no processor, no sub-processor, and no data-sharing agreement to
audit. The question of who else has access to this data has one answer: no one.

Meeting recordings are transcribed into plain text with no voice-to-identity matching, by
deliberate design. Attendees are a flat list you type in by hand, never inferred from a voice,
which is exactly the kind of biometric processing GDPR treats as a special category of
personal data. Removing a person, organization, project, or meeting deletes its file from
disk and scrubs every reference to it elsewhere in the vault: no soft delete, no backup copy
sitting in a cloud provider's retention window, no separate system to remember to purge. And
because the data is a folder of plain markdown, the person you're storing data about could, in
principle, open the same file you're looking at and read exactly what's recorded about them,
with no hidden fields and no analytics payload riding along underneath.

## What it looks like

People, organizations, and projects each get their own markdown file, linked to each other
the way Obsidian links notes: `[[id]]` wikilinks, with backlinks derived automatically. A
People graph clusters everyone by employer, one bubble per company sized by headcount. An
organization view shows a board of that company's projects and who's staffed on each. A
person view centers them with their direct relationships as labeled spokes. A project view is
a roster: who's on it, and in what role. Meeting recording captures both your microphone and
system audio, transcribes and cleans up the conversation, and writes a summary, all
on-device, saved as one more markdown file linked to a person, organization, or project.

## Requirements

- macOS 26 or later
- Apple Silicon (the on-device transcription and summarization models require MLX, which is
  Apple-Silicon-only; this app does not run on Intel Macs)

## Getting started

Open `maillage.xcodeproj` in Xcode, select the **Maillage** scheme, and run. On first launch
it'll ask where to keep your vault, a plain folder; pick anywhere, or accept the default.

For everything else, building, testing, the CI pipeline, releasing, and the exact vault file
format and its invariants, see [CLAUDE.md](CLAUDE.md).

## How it's built

[ARCHITECTURE.md](ARCHITECTURE.md) walks through the runtime architecture in detail: the
model layer, the vault read/write layer, `VaultStore`, the graph layout algorithms behind the
People and person-relationship views, and the full on-device meeting-recording pipeline: Core
Audio capture, MLX-based transcription, and MLX-based summarization.
