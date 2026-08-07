import Foundation
import Observation

/// Single source of truth for the loaded vault.
///
/// Views read entities from here and route every mutation through it, so the
/// in-memory state and the files on disk never diverge. Backlinks are **derived**:
/// relations are stored one-way on the source person, and this type inverts them in
/// memory so the target can display "Referenced by" without duplicating data.
@MainActor
@Observable
public final class VaultStore {
    public private(set) var location: VaultLocation
    public private(set) var snapshot = VaultSnapshot()

    /// Inverted relation index, rebuilt whenever the snapshot changes.
    public private(set) var backlinkIndex: [EntityID: [Backlink]] = [:]

    /// Set when a save or load fails, for display in the UI.
    public var lastError: String?

    private var reader: VaultReader
    private var writer: VaultWriter

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
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Points the store at a different vault folder and reloads.
    public func changeLocation(to newLocation: VaultLocation) {
        location = newLocation
        reader = VaultReader(location: newLocation)
        writer = VaultWriter(location: newLocation)
        load()
    }

    // MARK: Derived state

    private func rebuildBacklinks() {
        var index: [EntityID: [Backlink]] = [:]
        for person in snapshot.people.values {
            for relation in person.relations {
                index[relation.to.id, default: []].append(
                    Backlink(from: person.id, label: relation.label))
            }
        }
        // Stable ordering so the UI doesn't reshuffle between loads.
        for key in index.keys {
            index[key]?.sort {
                let left = displayName(for: $0.from) ?? $0.from
                let right = displayName(for: $1.from) ?? $1.from
                return (left, $0.label) < (right, $1.label)
            }
        }
        backlinkIndex = index
    }

    /// Relations pointing *at* `id`, derived from other people's files.
    public func backlinks(for id: EntityID) -> [Backlink] {
        backlinkIndex[id] ?? []
    }

    // MARK: Lookup

    public var allPeople: [Person] {
        snapshot.people.values.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    public var allOrganizations: [Organization] {
        snapshot.organizations.values.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    public var allProjects: [Project] {
        snapshot.projects.values.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    public var allEntities: [AnyEntity] {
        allPeople.map(AnyEntity.person)
            + allOrganizations.map(AnyEntity.organization)
            + allProjects.map(AnyEntity.project)
    }

    public func entity(id: EntityID) -> AnyEntity? {
        if let person = snapshot.people[id] { return .person(person) }
        if let org = snapshot.organizations[id] { return .organization(org) }
        if let project = snapshot.projects[id] { return .project(project) }
        return nil
    }

    /// Display name for `id`, or `nil` when the link is dangling.
    public func displayName(for id: EntityID) -> String? {
        entity(id: id)?.displayName
    }

    /// People employed by `organizationID`.
    public func members(ofOrganization organizationID: EntityID) -> [Person] {
        allPeople.filter { $0.organization?.id == organizationID }
    }

    /// People who list `projectID` in their `projects`.
    public func members(ofProject projectID: EntityID) -> [Person] {
        allPeople.filter { person in person.projects.contains { $0.to.id == projectID } }
    }

    /// Everyone on a project paired with the role they hold *there*.
    ///
    /// The roster the project view shows. Derived by scanning people, like every other
    /// membership query, so the project file stores nothing about who is on it.
    public func participants(ofProject projectID: EntityID)
        -> [(person: Person, role: String?)]
    {
        allPeople.compactMap { person in
            guard let membership = person.projects.first(where: { $0.to.id == projectID })
            else { return nil }
            return (person, membership.role)
        }
    }

    /// Every person bucketed by employer, for the clustered People graph.
    ///
    /// Organizations come in ``allOrganizations`` order with the unaffiliated bucket
    /// (`nil`) last, so cluster positions are derived from a stable index and the graph
    /// lays out the same way on every launch. Empty organizations are omitted — an anchor
    /// with nothing around it is just an isolated node.
    public func peopleGroupedByOrganization()
        -> [(organization: Organization?, people: [Person])]
    {
        var groups: [(organization: Organization?, people: [Person])] = []
        for org in allOrganizations {
            let people = members(ofOrganization: org.id)
            if !people.isEmpty { groups.append((org, people)) }
        }
        // A dangling employer counts as unaffiliated rather than vanishing: a hand-edited
        // link to a nonexistent org must not drop someone out of the graph entirely.
        let unaffiliated = allPeople.filter { person in
            guard let employer = person.organization else { return true }
            return snapshot.organizations[employer.id] == nil
        }
        if !unaffiliated.isEmpty { groups.append((nil, unaffiliated)) }
        return groups
    }

    /// Projects attached to an organization.
    public func projects(inOrganization organizationID: EntityID) -> [Project] {
        allProjects.filter { $0.organizations.contains(Wikilink(organizationID)) }
    }

    /// Every relation label already in use, most-used first.
    ///
    /// Derived rather than stored: the vocabulary *is* whatever is on disk, so labels
    /// need no separate config file and pruning a relation prunes its label with it.
    /// Most-used first because the labels someone reaches for repeatedly are the ones
    /// worth offering back to them.
    public var usedRelationLabels: [String] {
        var counts: [String: Int] = [:]
        for person in snapshot.people.values {
            for relation in person.relations {
                counts[relation.label, default: 0] += 1
            }
        }
        return counts.sorted {
            $0.value != $1.value
                ? $0.value > $1.value
                : $0.key.localizedStandardCompare($1.key) == .orderedAscending
        }
        .map(\.key)
    }

    /// Every project role already in use, most-used first.
    ///
    /// Same reasoning as ``usedRelationLabels``: the vocabulary is whatever is on disk, so
    /// "Lead" is offered back once it has been typed and needs no config file.
    public var usedProjectRoles: [String] {
        var counts: [String: Int] = [:]
        for person in snapshot.people.values {
            for membership in person.projects {
                guard let role = membership.role?.nilIfBlank else { continue }
                counts[role, default: 0] += 1
            }
        }
        return counts.sorted {
            $0.value != $1.value
                ? $0.value > $1.value
                : $0.key.localizedStandardCompare($1.key) == .orderedAscending
        }
        .map(\.key)
    }

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
        organizations: [Wikilink] = [],
        body: String = ""
    ) -> Project? {
        let id = writer.availableID(for: name, kind: .project)
        let project = Project(
            id: id, name: name, status: status, organizations: organizations,
            created: .today(), body: body)
        return persist(project) ? project : nil
    }

    // MARK: Updating

    @discardableResult
    public func update(_ person: Person) -> Bool { persist(person) }

    @discardableResult
    public func update(_ organization: Organization) -> Bool { persist(organization) }

    @discardableResult
    public func update(_ project: Project) -> Bool { persist(project) }

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

            switch kind {
            case .person: snapshot.people.removeValue(forKey: id)
            case .organization: snapshot.organizations.removeValue(forKey: id)
            case .project: snapshot.projects.removeValue(forKey: id)
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
                where project.organizations.contains(Wikilink(id)) {
                    project.organizations.removeAll { $0.id == id }
                    snapshot.projects[projectID] = project
                    try writer.write(project)
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
            lastError = nil
            return newID
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: Persistence helper

    private func persist<T: Entity & Encodable>(_ entity: T) -> Bool {
        do {
            try writer.write(entity)
            switch entity {
            case let person as Person: snapshot.people[person.id] = person
            case let org as Organization: snapshot.organizations[org.id] = org
            case let project as Project: snapshot.projects[project.id] = project
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

extension String {
    /// `nil` when the string is empty or only whitespace, so blank form fields are
    /// omitted from frontmatter instead of written as `""`.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
