import Foundation

/// Resolves where the vault lives on disk and creates its directory skeleton.
public struct VaultLocation: Hashable, Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The default vault: `~/Documents/Maillage`.
    public static var `default`: VaultLocation {
        let documents =
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        return VaultLocation(root: documents.appendingPathComponent("Maillage", isDirectory: true))
    }

    public func directory(for kind: EntityKind) -> URL {
        root.appendingPathComponent(kind.directoryName, isDirectory: true)
    }

    /// Path of the markdown file backing `id` for a given kind.
    public func fileURL(kind: EntityKind, id: EntityID) -> URL {
        directory(for: kind).appendingPathComponent("\(id).md")
    }

    /// Where a kind's logos live: `assets/people/`, `assets/organizations/`, …
    ///
    /// Partitioned by kind rather than one flat folder, because ids are only unique *within* a
    /// kind — ``VaultWriter/availableID(for:kind:prefix:reserved:)`` checks one directory, so
    /// `people/acme.md` and `projects/acme.md` can both exist. Mirroring the entity directories
    /// makes a collision between their logos impossible by construction.
    public func assetsDirectory(for kind: EntityKind) -> URL {
        root.appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent(kind.directoryName, isDirectory: true)
    }

    /// Path of the logo backing `id`, whether or not one exists. Always `.png` —
    /// ``ImageSquarer`` converts everything to one format on the way in.
    public func logoURL(kind: EntityKind, id: EntityID) -> URL {
        assetsDirectory(for: kind).appendingPathComponent("\(id).png")
    }

    /// Where a meeting's in-progress audio lives while it's being recorded and transcribed:
    /// `.maillage/recordings/<meeting-id>/`. App-private and inside the vault so it travels with
    /// it, and per-meeting rather than one flat folder so deleting a meeting's audio is deleting
    /// one directory, never a filter over a shared one.
    ///
    /// Nothing here survives past transcription — see the design doc's audio-retention
    /// promise — so unlike ``assetsDirectory(for:)`` this is never created eagerly by
    /// ``createSkeletonIfNeeded()``; it exists only from the moment a recording starts.
    public func recordingsDirectory(forMeeting id: EntityID) -> URL {
        recordingsRootDirectory.appendingPathComponent(id, isDirectory: true)
    }

    /// Parent of every in-progress recording, so the launch-time orphan sweep has one place to
    /// list rather than reconstructing the path itself.
    public var recordingsRootDirectory: URL {
        root.appendingPathComponent(".maillage", isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)
    }

    /// Where the local LLM's user-editable prompt templates live: `.maillage/prompts/`. Like
    /// ``recordingsRootDirectory``, never created eagerly by ``createSkeletonIfNeeded()`` — a
    /// template file is seeded here the first time a meeting is transcribed
    /// (``PromptTemplateStore``), not at vault creation, so an unrecorded vault has no prompts a
    /// user would find and wonder about.
    public func promptURL(named name: String) -> URL {
        root.appendingPathComponent(".maillage", isDirectory: true)
            .appendingPathComponent("prompts", isDirectory: true)
            .appendingPathComponent("\(name).md")
    }

    /// Creates the vault root, the three entity directories, their asset folders, and
    /// `.maillage/`. Safe to call repeatedly.
    public func createSkeletonIfNeeded() throws {
        let fm = FileManager.default
        for kind in EntityKind.allCases {
            try fm.createDirectory(at: directory(for: kind), withIntermediateDirectories: true)
            // Made eagerly alongside the entity directory, so the vault's shape is visible in
            // Finder before anything is in it and a write never has to create its own parent.
            // Skipped for a kind with no logos of its own — an empty `assets/meetings/` next
            // to two folders that actually hold something would just be Finder clutter.
            guard kind.supportsLogo else { continue }
            try fm.createDirectory(
                at: assetsDirectory(for: kind), withIntermediateDirectories: true)
        }
        try fm.createDirectory(
            at: recordingsRootDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true)
    }

    /// True when the vault root already exists on disk.
    public var exists: Bool {
        FileManager.default.fileExists(atPath: root.path)
    }
}
