import Foundation

/// A one-way, labeled link from one person to another.
///
/// Relations are stored **only** on the source person's file. The inverse is
/// never written to disk; ``VaultStore`` derives it in memory as a backlink.
public struct Relation: Hashable, Codable, Sendable, Identifiable {
    /// The person this relation points at.
    public var to: Wikilink
    /// Free-text label, e.g. `manager of`, `friend of`.
    public var label: String

    public var id: String { "\(to.id)|\(label)" }

    public init(to: Wikilink, label: String) {
        self.to = to
        self.label = label
    }

    public init(to id: EntityID, label: String) {
        self.init(to: Wikilink(id), label: label)
    }
}

/// A relation seen from the target's side. Derived, never persisted.
public struct Backlink: Hashable, Sendable, Identifiable {
    /// The person who declared the relation.
    public var from: EntityID
    public var label: String

    public var id: String { "\(from)|\(label)" }

    public init(from: EntityID, label: String) {
        self.from = from
        self.label = label
    }
}

/// Suggested relation labels offered in the editor. Free text is always allowed —
/// this list only exists to keep common labels spelled consistently.
public enum RelationLabel {
    public static let suggestions: [String] = [
        "friend of",
        "manager of",
        "reports to",
        "colleague of",
        "mentor of",
        "mentored by",
        "introduced me to",
        "introduced by",
        "partner of",
        "family of",
        "client of",
        "vendor to",
        "collaborator of",
        "knows",
    ]
}
