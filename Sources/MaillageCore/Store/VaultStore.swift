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

    /// People who list `organizationID` in their `organizations`.
    public func members(ofOrganization organizationID: EntityID) -> [Person] {
        allPeople.filter { $0.organizations.contains(Wikilink(organizationID)) }
    }

    /// People who list `projectID` in their `projects`.
    public func members(ofProject projectID: EntityID) -> [Person] {
        allPeople.filter { $0.projects.contains(Wikilink(projectID)) }
    }

    /// Projects attached to an organization.
    public func projects(inOrganization organizationID: EntityID) -> [Project] {
        allProjects.filter { $0.organizations.contains(Wikilink(organizationID)) }
    }

    // MARK: Creating

    /// Creates a named person. Pass `placeholder: true` with a `descriptor` for
    /// someone whose name you do not know yet.
    @discardableResult
    public func createPerson(
        firstname: String? = nil,
        lastname: String? = nil,
        email: String? = nil,
        descriptor: String? = nil,
        placeholder: Bool = false,
        organizations: [Wikilink] = [],
        projects: [Wikilink] = [],
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
            placeholder: placeholder,
            descriptor: descriptor?.nilIfBlank,
            organizations: organizations,
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
                if kind == .organization, person.organizations.contains(Wikilink(id)) {
                    person.organizations.removeAll { $0.id == id }
                    touched = true
                }
                if kind == .project, person.projects.contains(Wikilink(id)) {
                    person.projects.removeAll { $0.id == id }
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
