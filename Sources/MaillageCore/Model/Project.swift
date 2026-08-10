import Foundation

public enum ProjectStatus: String, Codable, CaseIterable, Sendable {
    case active
    case paused
    case done

    public var displayName: String { rawValue.capitalized }
}

/// A project that people can be linked to. Like ``Organization``, membership is
/// derived from each ``Person``'s `projects` list rather than stored here.
public struct Project: Entity, Codable {
    public var id: EntityID
    public var name: String
    public var status: ProjectStatus
    /// The organization this project belongs to.
    ///
    /// Singular: a piece of work is owned by one org, the same way a person has one
    /// employer, so ``VaultStore/projects(inOrganization:)`` partitions rather than
    /// overlaps and a project appears on exactly one board.
    public var organization: Wikilink?
    public var created: CalendarDay?
    public var body: String

    public var kind: EntityKind { .project }
    public var displayName: String { name.isEmpty ? id : name }

    public init(
        id: EntityID,
        name: String,
        status: ProjectStatus = .active,
        organization: Wikilink? = nil,
        created: CalendarDay? = nil,
        body: String = ""
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.organization = organization
        self.created = created
        self.body = body
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, name, status, organization, created
        /// Retired plural form, still read so existing vaults keep loading.
        case organizations
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(EntityID.self, forKey: .id)
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.status = try c.decodeIfPresent(ProjectStatus.self, forKey: .status) ?? .active
        // Ownership used to be a list, exactly as employment was on `Person`. Read the
        // singular key, falling back to the first entry of a legacy list so an older vault
        // still loads; saving rewrites the file in the singular form.
        if let single = try c.decodeIfPresent(Wikilink.self, forKey: .organization) {
            self.organization = single
        } else {
            self.organization = try c.decodeIfPresent([Wikilink].self, forKey: .organizations)?
                .first
        }
        self.created = try c.decodeIfPresent(CalendarDay.self, forKey: .created)
        self.body = ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(EntityKind.project.rawValue, forKey: .type)
        try c.encode(name, forKey: .name)
        try c.encode(status.rawValue, forKey: .status)
        try c.encodeIfPresent(organization, forKey: .organization)
        try c.encodeIfPresent(created, forKey: .created)
    }
}
