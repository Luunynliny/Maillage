import Foundation

/// Every write path: creating, updating, deleting and renaming entities. All of it funnels
/// through ``persist(_:)``, which is what keeps ``VaultStore/snapshot`` and the files on disk
/// from diverging.
extension VaultStore {
    // MARK: Creating

    /// Creates a named person. Pass `placeholder: true` with a `descriptor` for
    /// someone whose name you do not know yet.
    @discardableResult
    public func createPerson(
        firstname: String? = nil,
        lastname: String? = nil,
        email: String? = nil,
        role: String? = nil,
        descriptor: String? = nil,
        placeholder: Bool = false,
        organization: Wikilink? = nil,
        projects: [ProjectMembership] = [],
        body: String = ""
    ) -> Person? {
        let nameForSlug =
            placeholder
            ? (descriptor ?? "unnamed")
            : [firstname, lastname].compactMap { $0 }.joined(separator: " ")
        // Placeholders get an underscore prefix so they sort together and are obvious
        // when browsing the vault in Finder or Obsidian.
        let id = writer.availableID(
            for: nameForSlug, kind: .person, prefix: placeholder ? "_" : "")

        let person = Person(
            id: id,
            firstname: firstname?.nilIfBlank,
            lastname: lastname?.nilIfBlank,
            email: email?.nilIfBlank,
            role: role?.nilIfBlank,
            placeholder: placeholder,
            descriptor: descriptor?.nilIfBlank,
            organization: organization,
            projects: projects,
            created: .today(),
            body: body
        )
        return persist(person) ? person : nil
    }

    @discardableResult
    public func createOrganization(
        name: String, domain: String? = nil, body: String = ""
    ) -> Organization? {
        let id = writer.availableID(for: name, kind: .organization)
        let org = Organization(
            id: id, name: name, domain: domain?.nilIfBlank, created: .today(), body: body)
        return persist(org) ? org : nil
    }

    @discardableResult
    public func createProject(
        name: String,
        status: ProjectStatus = .active,
        organization: Wikilink? = nil,
        body: String = ""
    ) -> Project? {
        let id = writer.availableID(for: name, kind: .project)
        let project = Project(
            id: id, name: name, status: status, organization: organization,
            created: .today(), body: body)
        return persist(project) ? project : nil
    }

    /// Creates a meeting, id-prefixed with its date so files sort chronologically in Finder
    /// or Obsidian the same way ``allMeetings`` sorts them in the app — `2026-08-13-acme-standup`,
    /// not `acme-standup`. `writer.availableID` takes that prefix literally, ahead of the
    /// slugified title, exactly as it already does for a placeholder person's leading `_`.
    @discardableResult
    public func createMeeting(
        title: String,
        date: CalendarDay = .today(),
        duration: Int? = nil,
        organization: Wikilink? = nil,
        project: Wikilink? = nil,
        attendees: [Wikilink] = [],
        body: String = ""
    ) -> Meeting? {
        let id = writer.availableID(for: title, kind: .meeting, prefix: "\(date)-")
        let meeting = Meeting(
            id: id, title: title, date: date, duration: duration,
            organization: organization, project: project, attendees: attendees,
            created: .today(), body: body)
        return persist(meeting) ? meeting : nil
    }

    // MARK: Updating

    @discardableResult
    public func update(_ person: Person) -> Bool { persist(person) }

    @discardableResult
    public func update(_ organization: Organization) -> Bool { persist(organization) }

    @discardableResult
    public func update(_ project: Project) -> Bool { persist(project) }

    @discardableResult
    public func update(_ meeting: Meeting) -> Bool { persist(meeting) }

    /// Adds a one-way labeled relation from `sourceID` to `targetID`.
    ///
    /// Only the source person's file is touched — the inverse is never written.
    @discardableResult
    public func addRelation(from sourceID: EntityID, to targetID: EntityID, label: String) -> Bool {
        guard var person = snapshot.people[sourceID] else { return false }
        let relation = Relation(to: targetID, label: label)
        guard !person.relations.contains(relation) else { return true }
        person.relations.append(relation)
        return persist(person)
    }

    @discardableResult
    public func removeRelation(from sourceID: EntityID, relation: Relation) -> Bool {
        guard var person = snapshot.people[sourceID] else { return false }
        person.relations.removeAll { $0 == relation }
        return persist(person)
    }

    /// Makes `projectID`'s roster exactly `participants`, adding, updating and removing
    /// memberships to match.
    ///
    /// The mirror image of ``participants(ofProject:)``, and what the project editor saves:
    /// that sheet knows the whole intended roster, not which individual entries moved.
    /// Membership still lives on the person, so this writes people's files and never the
    /// project's — only those whose entry actually changed, so saving a project without
    /// touching its people rewrites nothing.
    @discardableResult
    public func setParticipants(
        ofProject projectID: EntityID, to participants: [(person: EntityID, role: String?)]
    ) -> Bool {
        let roster = Set(participants.map(\.person))
        var roles: [EntityID: String] = [:]
        for participant in participants {
            if let role = participant.role?.nilIfBlank { roles[participant.person] = role }
        }

        var succeeded = true
        // Snapshotted first: `persist` mutates `snapshot.people` inside the loop.
        for personID in Array(snapshot.people.keys) {
            guard var person = snapshot.people[personID] else { continue }
            let index = person.projects.firstIndex { $0.to.id == projectID }

            if roster.contains(personID) {
                if let index {
                    guard person.projects[index].role != roles[personID] else { continue }
                    person.projects[index].role = roles[personID]
                } else {
                    person.projects.append(
                        ProjectMembership(to: projectID, role: roles[personID]))
                }
            } else {
                guard index != nil else { continue }
                // Drops the role with the membership — a role only means something as part
                // of one.
                person.projects.removeAll { $0.to.id == projectID }
            }

            if !persist(person) { succeeded = false }
        }
        return succeeded
    }

    /// Fills in a placeholder person's real name and renames their file, rewriting
    /// every inbound `[[_old-id]]` reference so nothing is orphaned.
    @discardableResult
    public func resolvePlaceholder(
        _ id: EntityID, firstname: String?, lastname: String?, email: String? = nil
    ) -> Person? {
        guard var person = snapshot.people[id] else { return nil }

        person.firstname = firstname?.nilIfBlank
        person.lastname = lastname?.nilIfBlank
        if let email = email?.nilIfBlank { person.email = email }
        person.placeholder = false
        person.descriptor = nil

        guard persist(person) else { return nil }

        // The id was derived from the descriptor and prefixed with `_`; move it to a
        // slug matching the real name.
        let newID = writer.availableID(for: person.displayName, kind: .person)
        guard newID != id else { return person }
        guard renameEntity(kind: .person, from: id, to: newID) != nil else { return nil }
        return snapshot.people[newID]
    }

    // MARK: Deleting

    /// Deletes an entity and scrubs every reference to it, so no dangling links remain.
    @discardableResult
    public func delete(kind: EntityKind, id: EntityID) -> Bool {
        do {
            try writer.delete(kind: kind, id: id)
            // The logo goes with the entity. Left behind it would be an orphan file that a
            // later entity reusing the id would silently inherit as its own avatar.
            try writer.deleteLogo(kind: kind, id: id)
            logoImages.invalidate(kind: kind, id: id)
            logoIDs[kind]?.remove(id)

            switch kind {
            case .person: snapshot.people.removeValue(forKey: id)
            case .organization: snapshot.organizations.removeValue(forKey: id)
            case .project: snapshot.projects.removeValue(forKey: id)
            case .meeting: snapshot.meetings.removeValue(forKey: id)
            }

            for (personID, var person) in snapshot.people {
                var touched = false
                if kind == .person {
                    let before = person.relations.count
                    person.relations.removeAll { $0.to.id == id }
                    touched = person.relations.count != before
                }
                if kind == .organization, person.organization?.id == id {
                    person.organization = nil
                    touched = true
                }
                if kind == .project, person.projects.contains(where: { $0.to.id == id }) {
                    // Drops the role with it — a role only means something as part of a
                    // membership.
                    person.projects.removeAll { $0.to.id == id }
                    touched = true
                }
                if touched {
                    snapshot.people[personID] = person
                    try writer.write(person)
                }
            }

            if kind == .organization {
                for (projectID, var project) in snapshot.projects
                where project.organization == Wikilink(id) {
                    project.organization = nil
                    snapshot.projects[projectID] = project
                    try writer.write(project)
                }
            }

            // Nothing links *to* a meeting, so deleting one needs no scrub of its own — but
            // deleting a person, organization or project has to reach every meeting that
            // named them, the same as it already reaches every person's relations above.
            if kind == .person || kind == .organization || kind == .project {
                for (meetingID, var meeting) in snapshot.meetings {
                    var touched = false
                    if kind == .person, meeting.attendees.contains(where: { $0.id == id }) {
                        meeting.attendees.removeAll { $0.id == id }
                        touched = true
                    }
                    if kind == .organization, meeting.organization?.id == id {
                        meeting.organization = nil
                        touched = true
                    }
                    if kind == .project, meeting.project?.id == id {
                        meeting.project = nil
                        touched = true
                    }
                    if touched {
                        snapshot.meetings[meetingID] = meeting
                        try writer.write(meeting)
                    }
                }
            }

            rebuildBacklinks()
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: Renaming

    @discardableResult
    public func renameEntity(kind: EntityKind, from oldID: EntityID, to newID: EntityID)
        -> EntityID?
    {
        do {
            snapshot = try writer.rename(kind: kind, from: oldID, to: newID, in: snapshot)
            rebuildBacklinks()
            // `rename` moved the logo file with the markdown; catch the index up to it. Both
            // keys are touched because the image is the same one under a new name — this is
            // also the path `resolvePlaceholder` takes, where `_head-of-aa` becomes a real slug.
            logoImages.invalidate(kind: kind, id: oldID)
            logoImages.invalidate(kind: kind, id: newID)
            if logoIDs[kind]?.remove(oldID) != nil {
                logoIDs[kind, default: []].insert(newID)
            }
            lastError = nil
            return newID
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: Persistence helper

    func persist<T: Entity & Encodable>(_ entity: T) -> Bool {
        do {
            try writer.write(entity)
            switch entity {
            case let person as Person: snapshot.people[person.id] = person
            case let org as Organization: snapshot.organizations[org.id] = org
            case let project as Project: snapshot.projects[project.id] = project
            case let meeting as Meeting: snapshot.meetings[meeting.id] = meeting
            default: break
            }
            rebuildBacklinks()
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}
