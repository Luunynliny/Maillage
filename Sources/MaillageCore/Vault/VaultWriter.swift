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
        try writeAtomically(Data(contents.utf8), to: url)
    }

    /// Takes `Data` rather than a `String` so logos go through the same swap as markdown: an
    /// interrupted save can no more leave half a PNG behind than half a profile.
    private func writeAtomically(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: temp, options: .atomic)

        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: temp)
        } else {
            try fm.moveItem(at: temp, to: url)
        }
    }

    // MARK: Logos

    /// Stores `data` — already squared PNG, from ``ImageSquarer`` — as this entity's logo.
    public func writeLogo(_ data: Data, kind: EntityKind, id: EntityID) throws {
        try writeAtomically(data, to: location.logoURL(kind: kind, id: id))
    }

    /// Removes an entity's logo. A no-op when there isn't one, like ``delete(kind:id:)``.
    public func deleteLogo(kind: EntityKind, id: EntityID) throws {
        let url = location.logoURL(kind: kind, id: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Which entities of `kind` have a logo, read from the asset directory.
    ///
    /// The file's presence *is* the fact — there is no `logo:` frontmatter key to consult — so
    /// this scan is how a logo becomes known, exactly as backlinks are derived rather than
    /// stored. Dropping a PNG in by hand therefore works.
    public func logoIDs(kind: EntityKind) -> Set<EntityID> {
        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                at: location.assetsDirectory(for: kind),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
        else { return [] }
        return Set(
            contents
                .filter { $0.pathExtension.lowercased() == "png" }
                .map { $0.deletingPathExtension().lastPathComponent })
    }

    // MARK: Voiceprints

    /// Stores `data` — a small JSON blob, see ``Voiceprint`` — as this person's voiceprint.
    /// Same "a logo is a file, not a field" shape as ``writeLogo(_:kind:id:)``.
    public func writeVoiceprint(_ data: Data, personID: EntityID) throws {
        try writeAtomically(data, to: location.voiceprintURL(personID: personID))
    }

    /// Removes a person's voiceprint. A no-op when there isn't one, like ``deleteLogo(kind:id:)``.
    public func deleteVoiceprint(personID: EntityID) throws {
        let url = location.voiceprintURL(personID: personID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Which people have a voiceprint, read from the asset directory — derived, not stored,
    /// exactly like ``logoIDs(kind:)``.
    public func voiceprintIDs() -> Set<EntityID> {
        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                at: location.assetsDirectory(for: .person),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
        else { return [] }
        return Set(
            contents
                .filter { $0.pathExtension.lowercased() == "voiceprint" }
                .map { $0.deletingPathExtension().lastPathComponent })
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
        try renameStoredEntity(kind: kind, from: oldID, to: newID, in: &updated)
        try FileManager.default.removeItem(at: oldURL)

        // 2. Carry the logo across. The filename is the identity and a logo is named after it,
        // so leaving it behind would orphan the file and silently blank the avatar.
        let oldLogo = location.logoURL(kind: kind, id: oldID)
        if FileManager.default.fileExists(atPath: oldLogo.path) {
            let newLogo = location.logoURL(kind: kind, id: newID)
            try FileManager.default.createDirectory(
                at: newLogo.deletingLastPathComponent(), withIntermediateDirectories: true)
            // A file already sitting at the destination would make `moveItem` throw and abort a
            // rename that has already moved the markdown. It can only be a leftover, since the
            // guard above proved no entity holds `newID`.
            if FileManager.default.fileExists(atPath: newLogo.path) {
                try FileManager.default.removeItem(at: newLogo)
            }
            try FileManager.default.moveItem(at: oldLogo, to: newLogo)
        }

        // 2b. Carry the voiceprint across too, only people have one, same reasoning as the
        // logo above: the filename is the identity, and leaving it behind would orphan it.
        if kind == .person {
            let oldVoiceprint = location.voiceprintURL(personID: oldID)
            if FileManager.default.fileExists(atPath: oldVoiceprint.path) {
                let newVoiceprint = location.voiceprintURL(personID: newID)
                try FileManager.default.createDirectory(
                    at: newVoiceprint.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                if FileManager.default.fileExists(atPath: newVoiceprint.path) {
                    try FileManager.default.removeItem(at: newVoiceprint)
                }
                try FileManager.default.moveItem(at: oldVoiceprint, to: newVoiceprint)
            }
        }

        // 3. Repoint every inbound reference.
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

        // Nothing links *to* a meeting — attendance lives only on the meeting's own file —
        // so renaming one needed no repointing above. Renaming a person, organization or
        // project, though, has to reach every meeting that names them, the same as it
        // reaches every person's relations, organization and projects above. Its own method
        // rather than a fourth block inlined here, purely to keep `rename` itself under the
        // complexity budget documented on `cyclomatic_complexity` in `.swiftlint.yml` — the
        // repointing itself is no more entangled with the rest than the organization/project
        // block above already was.
        try repointMeetings(kind: kind, from: oldID, to: newID, in: &updated)

        return updated
    }

    /// Step 1 of ``rename``: writes the renamed entity under `newID` and drops the old key,
    /// for whichever one of the four snapshot dictionaries `kind` names.
    private func renameStoredEntity(
        kind: EntityKind, from oldID: EntityID, to newID: EntityID, in updated: inout VaultSnapshot
    ) throws {
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
        case .meeting:
            if var meeting = updated.meetings.removeValue(forKey: oldID) {
                meeting.id = newID
                updated.meetings[newID] = meeting
                try write(meeting)
            }
        }
    }

    /// Step 3's meeting pass: see the call site in ``rename`` for why this is split out.
    private func repointMeetings(
        kind: EntityKind, from oldID: EntityID, to newID: EntityID, in updated: inout VaultSnapshot
    ) throws {
        guard kind == .person || kind == .organization || kind == .project else { return }

        for (id, var meeting) in updated.meetings {
            var touched = false

            if kind == .person {
                for index in meeting.attendees.indices
                where meeting.attendees[index].id == oldID {
                    meeting.attendees[index].id = newID
                    touched = true
                }
            }
            if kind == .organization, meeting.organization?.id == oldID {
                meeting.organization?.id = newID
                touched = true
            }
            if kind == .project, meeting.project?.id == oldID {
                meeting.project?.id = newID
                touched = true
            }

            if touched {
                updated.meetings[id] = meeting
                try write(meeting)
            }
        }
    }
}
