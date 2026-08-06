import Foundation

/// The three kinds of things a vault can hold. The raw value is written to the
/// `type:` frontmatter key and decides which subdirectory the file lives in.
public enum EntityKind: String, Codable, CaseIterable, Sendable {
    case person
    case organization
    case project

    /// Vault subdirectory for this kind.
    public var directoryName: String {
        switch self {
        case .person: "people"
        case .organization: "organizations"
        case .project: "projects"
        }
    }

    public var displayName: String {
        switch self {
        case .person: "People"
        case .organization: "Organizations"
        case .project: "Projects"
        }
    }
}

/// Common surface shared by ``Person``, ``Organization`` and ``Project``.
public protocol Entity: Identifiable, Hashable, Sendable {
    var id: EntityID { get }
    var kind: EntityKind { get }
    /// Human-readable name shown in the sidebar, graph and detail pane.
    var displayName: String { get }
    /// Free-form markdown body stored below the closing `---`.
    var body: String { get }
}

extension Entity {
    public var wikilink: Wikilink { Wikilink(id) }
}

/// Type-erased entity, used by the sidebar, command palette and graph so they can
/// treat all three kinds uniformly.
public enum AnyEntity: Identifiable, Hashable, Sendable {
    case person(Person)
    case organization(Organization)
    case project(Project)

    public var id: EntityID {
        switch self {
        case .person(let p): p.id
        case .organization(let o): o.id
        case .project(let p): p.id
        }
    }

    public var kind: EntityKind {
        switch self {
        case .person: .person
        case .organization: .organization
        case .project: .project
        }
    }

    public var displayName: String {
        switch self {
        case .person(let p): p.displayName
        case .organization(let o): o.displayName
        case .project(let p): p.displayName
        }
    }

    public var body: String {
        switch self {
        case .person(let p): p.body
        case .organization(let o): o.body
        case .project(let p): p.body
        }
    }

    public var asPerson: Person? {
        if case .person(let p) = self { return p }
        return nil
    }
}
