import Foundation

/// A person profile.
///
/// A person may be a **placeholder** — someone you know exists but cannot name yet
/// ("the head of AA"). Placeholders carry a ``descriptor`` instead of a name and can
/// be linked into orgs, projects and relations exactly like a named person, then
/// resolved later via ``VaultStore/resolvePlaceholder(_:firstname:lastname:)``.
public struct Person: Entity, Codable {
    public var id: EntityID
    public var firstname: String?
    public var lastname: String?
    public var email: String?

    /// True while this person has no confirmed name.
    public var placeholder: Bool
    /// Stand-in label for a placeholder, e.g. `Head of AA`.
    public var descriptor: String?

    /// Organizations this person belongs to. Membership lives here and nowhere else.
    public var organizations: [Wikilink]
    /// Projects this person is involved in.
    public var projects: [Wikilink]
    /// One-way labeled relations to other people.
    public var relations: [Relation]

    public var created: CalendarDay?
    public var body: String

    public var kind: EntityKind { .person }

    public init(
        id: EntityID,
        firstname: String? = nil,
        lastname: String? = nil,
        email: String? = nil,
        placeholder: Bool = false,
        descriptor: String? = nil,
        organizations: [Wikilink] = [],
        projects: [Wikilink] = [],
        relations: [Relation] = [],
        created: CalendarDay? = nil,
        body: String = ""
    ) {
        self.id = id
        self.firstname = firstname
        self.lastname = lastname
        self.email = email
        self.placeholder = placeholder
        self.descriptor = descriptor
        self.organizations = organizations
        self.projects = projects
        self.relations = relations
        self.created = created
        self.body = body
    }

    public var displayName: String {
        let full = [firstname, lastname]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !full.isEmpty { return full }
        if let descriptor, !descriptor.isEmpty { return descriptor }
        return id
    }

    // MARK: Codable

    /// `body` is not part of the frontmatter — ``FrontmatterCodec`` supplies it
    /// separately from the markdown below the closing `---`.
    private enum CodingKeys: String, CodingKey {
        case id, type, firstname, lastname, email, placeholder, descriptor
        case organizations, projects, relations, created
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(EntityID.self, forKey: .id)
        self.firstname = try c.decodeIfPresent(String.self, forKey: .firstname)
        self.lastname = try c.decodeIfPresent(String.self, forKey: .lastname)
        self.email = try c.decodeIfPresent(String.self, forKey: .email)
        self.placeholder = try c.decodeIfPresent(Bool.self, forKey: .placeholder) ?? false
        self.descriptor = try c.decodeIfPresent(String.self, forKey: .descriptor)
        self.organizations = try c.decodeIfPresent([Wikilink].self, forKey: .organizations) ?? []
        self.projects = try c.decodeIfPresent([Wikilink].self, forKey: .projects) ?? []
        self.relations = try c.decodeIfPresent([Relation].self, forKey: .relations) ?? []
        self.created = try c.decodeIfPresent(CalendarDay.self, forKey: .created)
        self.body = ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(EntityKind.person.rawValue, forKey: .type)
        try c.encodeIfPresent(firstname, forKey: .firstname)
        try c.encodeIfPresent(lastname, forKey: .lastname)
        try c.encodeIfPresent(email, forKey: .email)
        try c.encode(placeholder, forKey: .placeholder)
        try c.encodeIfPresent(descriptor, forKey: .descriptor)
        if !organizations.isEmpty { try c.encode(organizations, forKey: .organizations) }
        if !projects.isEmpty { try c.encode(projects, forKey: .projects) }
        if !relations.isEmpty { try c.encode(relations, forKey: .relations) }
        try c.encodeIfPresent(created, forKey: .created)
    }
}
