import Foundation

public enum VaultWriteError: Error, LocalizedError {
    case idAlreadyExists(EntityID)
    case notFound(EntityID)

    public var errorDescription: String? {
        switch self {
        case .idAlreadyExists(let id): "An entry named '\(id)' already exists"
        case .notFound(let id): "No entry named '\(id)' was found"
        }
    }
}

/// Persists entities to the vault.
///
/// All writes are atomic: content is written to a temporary file and then swapped
/// into place, so an interrupted save can never leave a truncated profile behind.
public struct VaultWriter {
    public let location: VaultLocation

    public init(location: VaultLocation) {
        self.location = location
    }

    // MARK: Writing

    public func write<T: Entity & Encodable>(_ entity: T) throws {
        let contents = try FrontmatterCodec.encode(entity, body: entity.body)
        let url = location.fileURL(kind: entity.kind, id: entity.id)
        try writeAtomically(contents, to: url)
    }

    private func writeAtomically(_ contents: String, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try Data(contents.utf8).write(to: temp, options: .atomic)

        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: temp)
        } else {
            try fm.moveItem(at: temp, to: url)
        }
    }

    // MARK: Identity

    /// Finds a free id derived from `name`, appending `-2`, `-3`, … on collision.
    ///
    /// `reserved` covers ids created earlier in the same batch that are not yet on disk.
    public func availableID(
        for name: String, kind: EntityKind, prefix: String = "", reserved: Set<EntityID> = []
    ) -> EntityID {
        let base = Wikilink.slugify(name)
        let stem = base.isEmpty ? "untitled" : base
        var candidate = prefix + stem
        var counter = 2
        while reserved.contains(candidate)
            || FileManager.default.fileExists(
                atPath: location.fileURL(kind: kind, id: candidate).path)
        {
            candidate = "\(prefix)\(stem)-\(counter)"
            counter += 1
        }
        return candidate
    }

    // MARK: Deleting

    public func delete(kind: EntityKind, id: EntityID) throws {
        let url = location.fileURL(kind: kind, id: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    // MARK: Renaming

    /// Moves `oldID` to `newID` and rewrites every inbound `[[oldID]]` reference.
    ///
    /// Because ids are the only link target, renaming must touch every file that
    /// references this entity or the graph would silently lose edges. Returns the
    /// entities that were rewritten so the caller can refresh in-memory state.
    @discardableResult
    public func rename(
        kind: EntityKind,
        from oldID: EntityID,
        to newID: EntityID,
        in snapshot: VaultSnapshot
    ) throws -> VaultSnapshot {
        guard oldID != newID else { return snapshot }

        let oldURL = location.fileURL(kind: kind, id: oldID)
        let newURL = location.fileURL(kind: kind, id: newID)
        guard FileManager.default.fileExists(atPath: oldURL.path) else {
            throw VaultWriteError.notFound(oldID)
        }
        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            throw VaultWriteError.idAlreadyExists(newID)
        }

        var updated = snapshot

        // 1. Rewrite the entity itself under its new id.
        switch kind {
        case .person:
            if var person = updated.people.removeValue(forKey: oldID) {
                person.id = newID
                updated.people[newID] = person
                try write(person)
            }
        case .organization:
            if var org = updated.organizations.removeValue(forKey: oldID) {
                org.id = newID
                updated.organizations[newID] = org
                try write(org)
            }
        case .project:
            if var project = updated.projects.removeValue(forKey: oldID) {
                project.id = newID
                updated.projects[newID] = project
                try write(project)
            }
        }
        try FileManager.default.removeItem(at: oldURL)

        // 2. Repoint every inbound reference.
        for (id, var person) in updated.people {
            var touched = false

            if kind == .person {
                for index in person.relations.indices where person.relations[index].to.id == oldID {
                    person.relations[index].to.id = newID
                    touched = true
                }
            }
            if kind == .organization, person.organization?.id == oldID {
                person.organization?.id = newID
                touched = true
            }
            if kind == .project {
                // Only the link moves; the role rides along untouched.
                for index in person.projects.indices
                where person.projects[index].to.id == oldID {
                    person.projects[index].to.id = newID
                    touched = true
                }
            }

            if touched {
                updated.people[id] = person
                try write(person)
            }
        }

        if kind == .organization {
            for (id, var project) in updated.projects
            where project.organization?.id == oldID {
                project.organization?.id = newID
                updated.projects[id] = project
                try write(project)
            }
        }

        return updated
    }
}
