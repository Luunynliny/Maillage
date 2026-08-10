import Foundation

/// A company or organization. Membership is not stored here — it is derived by
/// scanning every ``Person``'s `organization` link.
public struct Organization: Entity, Codable {
    public var id: EntityID
    public var name: String
    public var domain: String?
    public var created: CalendarDay?
    public var body: String

    public var kind: EntityKind { .organization }
    public var displayName: String { name.isEmpty ? id : name }

    public init(
        id: EntityID,
        name: String,
        domain: String? = nil,
        created: CalendarDay? = nil,
        body: String = ""
    ) {
        self.id = id
        self.name = name
        self.domain = domain
        self.created = created
        self.body = body
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, name, domain, created
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(EntityID.self, forKey: .id)
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.domain = try c.decodeIfPresent(String.self, forKey: .domain)
        self.created = try c.decodeIfPresent(CalendarDay.self, forKey: .created)
        self.body = ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(EntityKind.organization.rawValue, forKey: .type)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(domain, forKey: .domain)
        try c.encodeIfPresent(created, forKey: .created)
    }
}
