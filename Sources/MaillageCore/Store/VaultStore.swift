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
private final class LogoCache {
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
@MainActor
@Observable
public final class VaultStore {
    public private(set) var location: VaultLocation
    public private(set) var snapshot = VaultSnapshot()

    /// Inverted relation index, rebuilt whenever the snapshot changes.
    public private(set) var backlinkIndex: [EntityID: [Backlink]] = [:]

    /// Which entities have a logo, per kind — derived from the files in `assets/`, never from
    /// frontmatter. Observable, so a row redraws the moment one is set or removed.
    public private(set) var logoIDs: [EntityKind: Set<EntityID>] = [:]

    /// Which people have a voiceprint — derived from `assets/people/*.voiceprint`, the same
    /// "file is the fact" shape as ``logoIDs``. Only people have one, so this is a flat set
    /// rather than keyed by kind.
    public private(set) var voiceprintIDs: Set<EntityID> = []

    /// Set when a save or load fails, for display in the UI.
    public var lastError: String?

    private var reader: VaultReader
    private var writer: VaultWriter
    private let logoImages = LogoCache()

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
            rebuildVoiceprintIDs()
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

    private func rebuildLogoIDs() {
        var index: [EntityKind: Set<EntityID>] = [:]
        for kind in EntityKind.allCases {
            index[kind] = writer.logoIDs(kind: kind)
        }
        logoIDs = index
    }

    private func rebuildVoiceprintIDs() {
        voiceprintIDs = writer.voiceprintIDs()
    }

    // MARK: Logos

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

    // MARK: Voiceprints

    /// Whether this person has a voiceprint on disk. Reads the observable index, same reasoning
    /// as ``hasLogo(kind:id:)``.
    public func hasVoiceprint(personID: EntityID) -> Bool {
        voiceprintIDs.contains(personID)
    }

    /// This person's stored voice signature, decoded, or `nil` if they have none — no cache,
    /// unlike ``logo(kind:id:)``: a voiceprint is only ever read when a new diarized speaker
    /// slot needs matching against every enrolled person, not once per frame like an avatar.
    public func voiceprint(personID: EntityID) -> Voiceprint? {
        guard hasVoiceprint(personID: personID),
            let data = try? Data(contentsOf: location.voiceprintURL(personID: personID))
        else { return nil }
        return try? JSONDecoder().decode(Voiceprint.self, from: data)
    }

    /// Folds a newly confirmed embedding into this person's stored voiceprint via
    /// ``Voiceprint/updated(_:confirming:)`` — an exponential moving average, not a snapshot, so
    /// this is called every time a speaker slot is confirmed or corrected against this person,
    /// not just the first time.
    @discardableResult
    public func setVoiceprint(personID: EntityID, confirming embedding: [Float]) -> Bool {
        do {
            let updated = Voiceprint.updated(voiceprint(personID: personID), confirming: embedding)
            let data = try JSONEncoder().encode(updated)
            try writer.writeVoiceprint(data, personID: personID)
            voiceprintIDs.insert(personID)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func removeVoiceprint(personID: EntityID) -> Bool {
        do {
            try writer.deleteVoiceprint(personID: personID)
            voiceprintIDs.remove(personID)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: Lookup

    public var allPeople: [Person] {
        snapshot.people.values.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    public var allOrganizations: [Organization] {
        snapshot.organizations.values.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    public var allProjects: [Project] {
        snapshot.projects.values.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    /// Most recent first, unlike the other three: a meeting list is read as "what's
    /// happened lately", not browsed alphabetically the way a roster of names is. A meeting
    /// with no date yet — mid-recording, or hand-seeded incompletely — sorts last rather
    /// than vanishing or claiming the top of a list it has no claim to.
    public var allMeetings: [Meeting] {
        snapshot.meetings.values.sorted {
            switch ($0.date, $1.date) {
            case (let left?, let right?): return left == right ? $0.id > $1.id : left > right
            case (nil, nil): return $0.id > $1.id
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }

    public var allEntities: [AnyEntity] {
        allPeople.map(AnyEntity.person)
            + allOrganizations.map(AnyEntity.organization)
            + allProjects.map(AnyEntity.project)
            + allMeetings.map(AnyEntity.meeting)
    }

    public func entity(id: EntityID) -> AnyEntity? {
        if let person = snapshot.people[id] { return .person(person) }
        if let org = snapshot.organizations[id] { return .organization(org) }
        if let project = snapshot.projects[id] { return .project(project) }
        if let meeting = snapshot.meetings[id] { return .meeting(meeting) }
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

    /// Projects owned by an organization.
    public func projects(inOrganization organizationID: EntityID) -> [Project] {
        allProjects.filter { $0.organization == Wikilink(organizationID) }
    }

    /// A person's meeting history — every meeting that lists them as an attendee, most
    /// recent first. What ``EntityDetails`` shows on a person's own pane; the payoff this
    /// whole entity exists for.
    public func meetings(withPerson personID: EntityID) -> [Meeting] {
        allMeetings.filter { meeting in meeting.attendees.contains { $0.id == personID } }
    }

    /// Meetings held with an organization.
    public func meetings(inOrganization organizationID: EntityID) -> [Meeting] {
        allMeetings.filter { $0.organization?.id == organizationID }
    }

    /// Meetings held about a project.
    public func meetings(onProject projectID: EntityID) -> [Meeting] {
        allMeetings.filter { $0.project?.id == projectID }
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
            // Same reasoning, people only: a voiceprint left behind would let a later person
            // who reuses this id inherit someone else's voice as their own.
            if kind == .person {
                try writer.deleteVoiceprint(personID: id)
                voiceprintIDs.remove(id)
            }

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
            // `rename` moved the voiceprint file too, people only — catch the index up to it.
            if kind == .person, voiceprintIDs.remove(oldID) != nil {
                voiceprintIDs.insert(newID)
            }
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

extension String {
    /// `nil` when the string is empty or only whitespace, so blank form fields are
    /// omitted from frontmatter instead of written as `""`.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
