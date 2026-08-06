import Foundation
import Yams

public enum FrontmatterError: Error, LocalizedError {
    case missingFrontmatter(path: String)
    case unterminatedFrontmatter(path: String)

    public var errorDescription: String? {
        switch self {
        case .missingFrontmatter(let path):
            "No YAML frontmatter found in \(path)"
        case .unterminatedFrontmatter(let path):
            "Frontmatter in \(path) is missing its closing '---'"
        }
    }
}

/// Splits and joins markdown files of the form:
/// ```
/// ---
/// key: value
/// ---
///
/// body text
/// ```
///
/// The body is treated as opaque text and round-trips byte-for-byte, so notes are
/// never mangled by a save.
public enum FrontmatterCodec {
    /// Separates the raw YAML frontmatter from the markdown body.
    public static func split(_ contents: String, path: String = "<memory>") throws -> (
        yaml: String, body: String
    ) {
        // Normalise CRLF so hand-edited or Windows-synced files parse identically.
        let text = contents.replacingOccurrences(of: "\r\n", with: "\n")
        guard text.hasPrefix("---\n") || text == "---" || text.hasPrefix("---\r") else {
            throw FrontmatterError.missingFrontmatter(path: path)
        }

        let afterOpening = text.dropFirst(4)  // drop "---\n"
        // The closing fence is a line consisting solely of "---".
        guard let fence = afterOpening.range(of: "\n---") else {
            throw FrontmatterError.unterminatedFrontmatter(path: path)
        }

        let yaml = String(afterOpening[afterOpening.startIndex..<fence.lowerBound])
        var rest = String(afterOpening[fence.upperBound...])
        // Trim the remainder of the closing fence line, keeping the body intact.
        if let newline = rest.firstIndex(of: "\n") {
            rest = String(rest[rest.index(after: newline)...])
        } else {
            rest = ""
        }
        // Drop exactly one blank separator line, the shape `write` produces.
        if rest.hasPrefix("\n") { rest = String(rest.dropFirst()) }
        // `encode` appends a trailing newline; strip it so body text round-trips
        // unchanged rather than growing a newline on every save.
        if rest.hasSuffix("\n") { rest.removeLast() }

        return (yaml, rest)
    }

    /// Decodes an entity from a full markdown file.
    public static func decode<T: Decodable>(
        _ type: T.Type, from contents: String, path: String = "<memory>"
    ) throws -> (value: T, body: String) {
        let (yaml, body) = try split(contents, path: path)
        let decoder = YAMLDecoder()
        let value = try decoder.decode(type, from: yaml, userInfo: [:])
        return (value, body)
    }

    /// Renders an entity back into a full markdown file.
    ///
    /// Key order is preserved from the encoder so diffs stay stable between saves.
    public static func encode<T: Encodable>(_ value: T, body: String) throws -> String {
        let encoder = YAMLEncoder()
        encoder.options.sortKeys = false
        encoder.options.lineBreak = .ln
        // Prevent libyaml from wrapping long values (e.g. a list of wikilinks)
        // onto continuation lines, which would hurt readability and git diffs.
        encoder.options.width = -1

        var yaml = try encoder.encode(value)
        if yaml.hasSuffix("\n") { yaml.removeLast() }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBody.isEmpty {
            return "---\n\(yaml)\n---\n"
        }
        return "---\n\(yaml)\n---\n\n\(trimmedBody)\n"
    }
}
