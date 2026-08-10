import Foundation

/// Resolves where the vault lives on disk and creates its directory skeleton.
public struct VaultLocation: Hashable, Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The default vault: `~/Documents/Maillage`.
    public static var `default`: VaultLocation {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
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

    /// App-private settings, kept inside the vault so it travels with the data.
    public var configFileURL: URL {
        root.appendingPathComponent(".maillage", isDirectory: true)
            .appendingPathComponent("config.yaml")
    }

    /// Creates the vault root, the three entity directories, their asset folders, and
    /// `.maillage/`. Safe to call repeatedly.
    public func createSkeletonIfNeeded() throws {
        let fm = FileManager.default
        for kind in EntityKind.allCases {
            try fm.createDirectory(at: directory(for: kind), withIntermediateDirectories: true)
            // Made eagerly alongside the entity directory, so the vault's shape is visible in
            // Finder before anything is in it and a write never has to create its own parent.
            try fm.createDirectory(
                at: assetsDirectory(for: kind), withIntermediateDirectories: true)
        }
        try fm.createDirectory(
            at: configFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    /// True when the vault root already exists on disk.
    public var exists: Bool {
        FileManager.default.fileExists(atPath: root.path)
    }
}
