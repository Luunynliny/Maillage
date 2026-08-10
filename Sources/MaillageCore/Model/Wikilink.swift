import Foundation

/// Stable identity of an entity. Always equal to the vault filename stem.
public typealias EntityID = String

/// An Obsidian-style `[[id]]` reference.
///
/// Encodes to `"[[id]]"` so vault files stay readable in Obsidian, while the
/// rest of the app works with the bare ``EntityID``. Decoding tolerates a bare
/// id (no brackets) so hand-edited files keep working.
public struct Wikilink: Hashable, Codable, Sendable {
    public var id: EntityID

    public init(_ id: EntityID) {
        self.id = id
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self.id = Wikilink.parse(raw) ?? raw.trimmingCharacters(in: .whitespaces)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(formatted)
    }

    public var formatted: String { "[[\(id)]]" }

    /// Extracts the id from `[[id]]`, returning `nil` when `raw` is not a wikilink.
    /// Supports Obsidian's `[[id|display]]` and `[[id#heading]]` forms by keeping
    /// only the target portion.
    public static func parse(_ raw: String) -> EntityID? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[["), trimmed.hasSuffix("]]"), trimmed.count > 4 else {
            return nil
        }
        var inner = String(trimmed.dropFirst(2).dropLast(2))
        if let pipe = inner.firstIndex(of: "|") {
            inner = String(inner[inner.startIndex..<pipe])
        }
        if let hash = inner.firstIndex(of: "#") {
            inner = String(inner[inner.startIndex..<hash])
        }
        let id = inner.trimmingCharacters(in: .whitespaces)
        return id.isEmpty ? nil : id
    }

    /// Converts a display name into a filename-safe slug.
    ///
    /// Diacritics are folded (`Zoé Müller` → `zoe-muller`) so ids stay ASCII and
    /// filesystem-portable.
    public static func slugify(_ input: String) -> String {
        let folded =
            input
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: .init(identifier: "en_US")
            )
            .lowercased()

        var out = ""
        var lastWasDash = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                out.append("-")
                lastWasDash = true
            }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
