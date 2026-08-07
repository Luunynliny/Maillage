import Foundation

/// A person's involvement in one project, with what they do there.
///
/// Shaped like ``Relation``: a `to` link plus a free-text label. The role belongs here
/// rather than on ``Person/role`` because the same person leads one project and reviews
/// another, and it belongs here rather than on the project because **membership lives on
/// the person** — a project's roster is derived by scanning people.
public struct ProjectMembership: Hashable, Codable, Sendable, Identifiable {
    /// The project this person is on.
    public var to: Wikilink
    /// What they do on it, e.g. `Lead`, `Reviewer`. Free text, like ``Person/role``.
    public var role: String?

    /// A person is on a project once, so the target id identifies the membership.
    public var id: EntityID { to.id }

    public init(to: Wikilink, role: String? = nil) {
        self.to = to
        self.role = role
    }

    public init(to id: EntityID, role: String? = nil) {
        self.init(to: Wikilink(id), role: role)
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case to, role
    }

    /// Accepts either form, so `projects:` lists written by hand keep working:
    ///
    /// ```yaml
    /// projects:
    ///   - to: "[[maillage]]"
    ///     role: Lead
    ///   - "[[atlas]]"
    /// ```
    public init(from decoder: Decoder) throws {
        if let bare = try? decoder.singleValueContainer().decode(Wikilink.self) {
            self.init(to: bare)
        } else {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                to: try c.decode(Wikilink.self, forKey: .to),
                role: try c.decodeIfPresent(String.self, forKey: .role))
        }
    }

    /// Collapses back to a bare `"[[id]]"` when there is no role, so adding the field
    /// leaves untouched memberships byte-identical on disk.
    public func encode(to encoder: Encoder) throws {
        guard let role, !role.isEmpty else {
            var container = encoder.singleValueContainer()
            try container.encode(to)
            return
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(to, forKey: .to)
        try c.encode(role, forKey: .role)
    }
}
