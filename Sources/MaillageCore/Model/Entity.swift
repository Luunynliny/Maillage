import Foundation

/// The three kinds of things a vault can hold. The raw value is written to the
/// `type:` frontmatter key and decides which subdirectory the file lives in.
public enum EntityKind: String, Codable, CaseIterable, Sendable {
    case person
    case organization
    case project
    case meeting

    /// Vault subdirectory for this kind.
    public var directoryName: String {
        switch self {
        case .person: "people"
        case .organization: "organizations"
        case .project: "projects"
        case .meeting: "meetings"
        }
    }

    public var displayName: String {
        switch self {
        case .person: "People"
        case .organization: "Organizations"
        case .project: "Projects"
        case .meeting: "Meetings"
        }
    }

    /// Whether this kind keeps a logo in `assets/`. False only for ``meeting``: a
    /// conversation has no picture of its own, so ``VaultLocation/createSkeletonIfNeeded()``
    /// skips making it an asset folder, and every meeting avatar falls back to its glyph.
    public var supportsLogo: Bool {
        switch self {
        case .person, .organization, .project: true
        case .meeting: false
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

extension EntityKind {
    /// What the markdown body is called for this kind.
    ///
    /// Same storage everywhere, different meaning: prose about a person or organization
    /// is a note you keep, while a project's prose describes the work itself.
    public var bodyTitle: String {
        switch self {
        case .person, .organization: "Notes"
        case .project: "Description"
        // Unused in practice: ``MeetingView`` renders a meeting's body itself, and
        // ``EntityDetails`` skips its generic body block for this kind precisely so the
        // generated "## Summary"/"## Transcript" markdown is never dumped as raw text
        // *and* rendered properly in the same pane. Kept for exhaustiveness and for whatever
        // reads a meeting's body generically next.
        case .meeting: "Transcript"
        }
    }

    /// The glyph an entity of this kind wears until it has a logo of its own.
    ///
    /// Filled variants, because they are drawn small and inside a tinted disc — an outline
    /// glyph at 20pt reads as a thin scribble against the fill behind it.
    public var symbolName: String {
        switch self {
        case .person: "person.fill"
        case .organization: "building.2.fill"
        case .project: "folder.fill"
        case .meeting: "calendar"
        }
    }
}

/// Type-erased entity, used by the sidebar, command palette and graph so they can
/// treat all three kinds uniformly.
public enum AnyEntity: Identifiable, Hashable, Sendable {
    case person(Person)
    case organization(Organization)
    case project(Project)
    case meeting(Meeting)

    public var id: EntityID {
        switch self {
        case .person(let p): p.id
        case .organization(let o): o.id
        case .project(let p): p.id
        case .meeting(let m): m.id
        }
    }

    public var kind: EntityKind {
        switch self {
        case .person: .person
        case .organization: .organization
        case .project: .project
        case .meeting: .meeting
        }
    }

    public var displayName: String {
        switch self {
        case .person(let p): p.displayName
        case .organization(let o): o.displayName
        case .project(let p): p.displayName
        case .meeting(let m): m.displayName
        }
    }

    public var body: String {
        switch self {
        case .person(let p): p.body
        case .organization(let o): o.body
        case .project(let p): p.body
        case .meeting(let m): m.body
        }
    }

    public var bodyTitle: String { kind.bodyTitle }

    public var asPerson: Person? {
        if case .person(let p) = self { return p }
        return nil
    }
}
