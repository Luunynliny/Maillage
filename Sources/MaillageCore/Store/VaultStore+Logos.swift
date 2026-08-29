import AppKit
import Foundation

/// A logo is a file, not a field — see CLAUDE.md. This extension is everything that reads or
/// writes `assets/<kind>/<id>.png` and keeps ``VaultStore/logoIDs`` in sync with it.
extension VaultStore {
    func rebuildLogoIDs() {
        var index: [EntityKind: Set<EntityID>] = [:]
        for kind in EntityKind.allCases {
            index[kind] = writer.logoIDs(kind: kind)
        }
        logoIDs = index
    }

    /// Whether this entity has a logo on disk.
    ///
    /// Reads the observable index rather than touching the filesystem, so it's cheap enough for
    /// a view body and a change to it redraws the row.
    public func hasLogo(kind: EntityKind, id: EntityID) -> Bool {
        logoIDs[kind]?.contains(id) == true
    }

    /// This entity's logo, decoded and memoized, or `nil` if it has none.
    ///
    /// Returns `nil` rather than throwing on a file that won't decode: a corrupt PNG in the
    /// vault means the avatar falls back to its glyph, which is the display-side reading of
    /// *a malformed file is an issue, not a crash*. Import is where a bad image is reported,
    /// because that's where someone chose it and can pick another.
    public func logo(kind: EntityKind, id: EntityID) -> NSImage? {
        guard hasLogo(kind: kind, id: id) else { return nil }
        return logoImages.image(kind: kind, id: id) {
            NSImage(contentsOf: location.logoURL(kind: kind, id: id))
        }
    }

    /// Converts an image file and stores it as this entity's logo.
    ///
    /// Throws what ``ImageSquarer`` throws, so an editor can name the file that failed. A write
    /// failure lands in ``lastError`` like every other, and returns `false`.
    @discardableResult
    public func setLogo(kind: EntityKind, id: EntityID, from url: URL) -> Bool {
        do {
            try setLogo(kind: kind, id: id, pngData: ImageSquarer.squarePNG(contentsOf: url))
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Stores already-squared PNG data — what a ``LogoField`` holds after a pick, so the bytes
    /// behind the preview are the bytes that get written.
    @discardableResult
    public func setLogo(kind: EntityKind, id: EntityID, pngData: Data) -> Bool {
        do {
            try writer.writeLogo(pngData, kind: kind, id: id)
            logoImages.invalidate(kind: kind, id: id)
            logoIDs[kind, default: []].insert(id)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func removeLogo(kind: EntityKind, id: EntityID) -> Bool {
        do {
            try writer.deleteLogo(kind: kind, id: id)
            logoImages.invalidate(kind: kind, id: id)
            logoIDs[kind]?.remove(id)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}
