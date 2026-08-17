import Foundation

/// Read-only queries derived from ``VaultStore/snapshot``. Nothing here is stored — a project's
/// roster, a person's meeting history, the used-label vocabulary — all of it is recomputed from
/// the loaded files rather than cached, so there is never a second copy to fall out of sync.
extension VaultStore {
    // MARK: Backlinks

    func rebuildBacklinks() {
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
}
