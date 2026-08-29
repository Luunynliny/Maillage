# maillage

A personal CRM that runs on your own machine.

People, organizations and projects live as plain markdown files with YAML frontmatter, the same
format Obsidian itself uses, so the data is yours: readable in any text editor, diffable,
versionable with git, and never locked into a proprietary format. Labeled relationships between
people are drawn as a network you can walk out from — one hop, two, three — clustered by
employer and laid out deterministically rather than simulated, so the same vault always looks
the same way twice.

## Why

Most CRMs put your network of contacts and your notes about them on someone else's server.
maillage doesn't. It's built for one person, running entirely on one machine, with no account,
no cloud, and nothing that needs a network connection to work.

## Everything runs locally

There is no backend in the usual sense. `npm start` runs a small Node server on `localhost` that
reads and writes one folder — `~/Documents/Maillage` by default — and serves a page that draws
it. The server binds to loopback and nothing else can reach it. There is no database, no sync
service, no account, no API key, and no telemetry endpoint: search the source for `fetch(` and
every call goes to the process on your own machine.

## GDPR-compliant by nature, not by policy

A privacy policy is a promise about what a company does with your data. maillage doesn't need
one: there's no company in the loop, and nowhere for the data to go. Nothing is transmitted to a
third party, so there's no processor, no sub-processor, and no data-sharing agreement to audit.
The question of who else has access to this data has one answer: no one.

Removing a person, organization or project deletes its file from disk and scrubs every reference
to it elsewhere in the vault: no soft delete, no tombstone, no backup copy sitting in a cloud
provider's retention window, no separate system to remember to purge. And because the data is a
folder of plain markdown, the person you're storing data about could, in principle, open the
same file you're looking at and read exactly what's recorded about them, with no hidden fields
and no analytics payload riding along underneath.

## What it looks like

People, organizations and projects each get their own markdown file, linked to each other the
way Obsidian links notes: `[[id]]` wikilinks, with backlinks derived automatically. Which view
you get depends on what you select, because each selection is a different question:

| Selected        | You see                                                                      |
| --------------- | ---------------------------------------------------------------------------- |
| Nothing         | One bubble per employer, sized by headcount — the shape of the whole network |
| An organization | A board of that company's projects and who is staffed on each                |
| A person        | Them at the centre of their relationship network                             |
| A project       | A roster: who's on it, and in what role                                      |

The person view is the one this app exists for. It starts as their direct relations and opens
out: **depth 1, 2 or 3**, drawing not just their spokes but every edge _between_ the people
reached — so a cluster, a triangle or a bridge between two parts of your network is visible
rather than implied. A legend lists every relation label and every employer in view; clicking
one dims the rest without moving anything, so the picture stays the same picture while you
interrogate it. Search highlights in place. You can pan, zoom, and click any node to re-root the
graph on them, with a breadcrumb trail back.

## Getting started

```
npm ci
npm start
```

Then open the URL it prints. On first launch it uses `~/Documents/Maillage`, creating it if it
isn't there; the path at the bottom of the sidebar changes it.

Requires Node 22.6 or later (24+ recommended). Any browser.

For development, `npm run dev` runs the same server with Vite mounted inside it, so there is one
process and one port either way. `npm run check` runs everything CI does.

For the exact vault file format and the invariants the tests enforce, see [CLAUDE.md](CLAUDE.md).
[ARCHITECTURE.md](ARCHITECTURE.md) walks through how the running app is put together.
