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

    /// App-private settings, kept inside the vault so it travels with the data.
    public var configFileURL: URL {
        root.appendingPathComponent(".maillage", isDirectory: true)
            .appendingPathComponent("config.yaml")
    }

    /// Creates the vault root, the three entity directories, and `.maillage/`.
    /// Safe to call repeatedly.
    public func createSkeletonIfNeeded() throws {
        let fm = FileManager.default
        for kind in EntityKind.allCases {
            try fm.createDirectory(at: directory(for: kind), withIntermediateDirectories: true)
        }
        try fm.createDirectory(
            at: configFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    /// True when the vault root already exists on disk.
    public var exists: Bool {
        FileManager.default.fileExists(atPath: root.path)
    }
}
