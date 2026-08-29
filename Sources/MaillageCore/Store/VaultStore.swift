import AppKit
import Foundation
import Observation

/// Decoded logos, kept out of ``VaultStore``'s observable storage.
///
/// A view asks for a logo *while* it renders, and filling a memo on an `@Observable` property
/// during a render is a mutation SwiftUI is entitled to loop on. A plain reference type is
/// invisible to observation, so caching a decode can't invalidate the view that triggered it —
/// what a view *does* observe is ``VaultStore/logoIDs``, which changes only when a logo is
/// actually added or removed.
@MainActor
final class LogoCache {
    /// `nil` values are cached too: a file that won't decode should be attempted once, not on
    /// every frame of a scroll.
    private var images: [String: NSImage?] = [:]

    private func key(_ kind: EntityKind, _ id: EntityID) -> String { "\(kind.rawValue)/\(id)" }

    func image(kind: EntityKind, id: EntityID, load: () -> NSImage?) -> NSImage? {
        let key = key(kind, id)
        if let cached = images[key] { return cached }
        let loaded = load()
        images[key] = loaded
        return loaded
    }

    func invalidate(kind: EntityKind, id: EntityID) {
        images.removeValue(forKey: key(kind, id))
    }

    func removeAll() {
        images.removeAll()
    }
}

/// Single source of truth for the loaded vault.
///
/// Views read entities from here and route every mutation through it, so the
/// in-memory state and the files on disk never diverge. Backlinks are **derived**:
/// relations are stored one-way on the source person, and this type inverts them in
/// memory so the target can display "Referenced by" without duplicating data.
///
/// Split across sibling files by concern — this file holds only state and loading;
/// see ``VaultStore``'s extensions in `VaultStore+Derived.swift`, `VaultStore+Logos.swift`
/// and `VaultStore+CRUD.swift`. `reader`, `writer`, `logoImages` and `persist(_:)` are
/// `internal` rather than `private` so those sibling extensions can reach them — none of
/// it is `public`, so the framework's external surface is unchanged.
@MainActor
@Observable
public final class VaultStore {
    public private(set) var location: VaultLocation
    // `internal(set)`, not `private(set)`: these are mutated from the `VaultStore+Derived`,
    // `+Logos` and `+CRUD` extensions in sibling files, and Swift's `private` is file-scoped.
    public internal(set) var snapshot = VaultSnapshot()

    /// Inverted relation index, rebuilt whenever the snapshot changes.
    public internal(set) var backlinkIndex: [EntityID: [Backlink]] = [:]

    /// Which entities have a logo, per kind — derived from the files in `assets/`, never from
    /// frontmatter. Observable, so a row redraws the moment one is set or removed.
    public internal(set) var logoIDs: [EntityKind: Set<EntityID>] = [:]

    /// Set when a save or load fails, for display in the UI.
    public var lastError: String?

    var reader: VaultReader
    var writer: VaultWriter
    let logoImages = LogoCache()

    public init(location: VaultLocation = .default) {
        self.location = location
        self.reader = VaultReader(location: location)
        self.writer = VaultWriter(location: location)
    }

    // MARK: Loading

    public func load() {
        do {
            try location.createSkeletonIfNeeded()
            snapshot = try reader.load()
            rebuildBacklinks()
            // Reload means the files may have changed underneath us — Reload Vault exists
            // precisely for editing the vault in Finder or Obsidian — so decoded logos can't
            // be trusted.
            logoImages.removeAll()
            rebuildLogoIDs()
            sweepOrphanedRecordings()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Deletes any leftover `.maillage/recordings/<id>/` directory whose meeting already has a
    /// transcript. A crash between transcription finishing and `MeetingRecorder` removing the
    /// directory would otherwise leave audio on disk forever — the deletion promise has to hold
    /// on the crash path, not just the happy one.
    private func sweepOrphanedRecordings() {
        let fm = FileManager.default
        guard
            let ids = try? fm.contentsOfDirectory(atPath: location.recordingsRootDirectory.path)
        else { return }
        for id in ids {
            guard let meeting = snapshot.meetings[id],
                !TranscriptCodec.split(meeting.body).segments.isEmpty
            else { continue }
            try? fm.removeItem(at: location.recordingsDirectory(forMeeting: id))
        }
    }

    /// Points the store at a different vault folder and reloads.
    public func changeLocation(to newLocation: VaultLocation) {
        location = newLocation
        reader = VaultReader(location: newLocation)
        writer = VaultWriter(location: newLocation)
        load()
    }
}

extension String {
    /// `nil` when the string is empty or only whitespace, so blank form fields are
    /// omitted from frontmatter instead of written as `""`.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
