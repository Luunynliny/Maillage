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
    /// Organizations this project belongs to or is run with.
    public var organizations: [Wikilink]
    public var created: CalendarDay?
    public var body: String

    public var kind: EntityKind { .project }
    public var displayName: String { name.isEmpty ? id : name }

    public init(
        id: EntityID,
        name: String,
        status: ProjectStatus = .active,
        organizations: [Wikilink] = [],
        created: CalendarDay? = nil,
        body: String = ""
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.organizations = organizations
        self.created = created
        self.body = body
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, name, status, organizations, created
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(EntityID.self, forKey: .id)
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.status = try c.decodeIfPresent(ProjectStatus.self, forKey: .status) ?? .active
        self.organizations = try c.decodeIfPresent([Wikilink].self, forKey: .organizations) ?? []
        self.created = try c.decodeIfPresent(CalendarDay.self, forKey: .created)
        self.body = ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(EntityKind.project.rawValue, forKey: .type)
        try c.encode(name, forKey: .name)
        try c.encode(status.rawValue, forKey: .status)
        if !organizations.isEmpty { try c.encode(organizations, forKey: .organizations) }
        try c.encodeIfPresent(created, forKey: .created)
    }
}
