import Foundation

/// Splits and joins the "## Transcript" section of a ``Meeting``'s markdown body.
///
/// Mirrors ``FrontmatterCodec``'s job one level down: that type separates the YAML header
/// from the body, this one separates the body's opaque preamble (an eventual "## Summary"
/// section, written by a later phase) from the one part of the body this type actually
/// understands. The preamble round-trips byte-for-byte, exactly like a person's notes do.
///
/// One line per segment:
/// ```
/// **Marie Dupont** (00:15) Oui, mais il faut wire le canary d'abord.
/// ```
/// The timestamp is `MM:SS`, or `H:MM:SS` once the offset reaches an hour — see
/// ``formatTimestamp(seconds:)``. A speaker name is never expected to contain `**`, so the
/// name capture can stop at the next one; the utterance itself is captured to the end of the
/// line, so a literal `(` or `)` inside it — someone saying a parenthetical — needs no
/// escaping. A literal newline inside an utterance is escaped to `\n` on the way out and
/// restored on the way in, which is the one thing that *would* otherwise break the one-line
/// shape.
public enum TranscriptCodec {
    /// The heading this type looks for. Kept as a constant because ``split`` and ``join``
    /// must agree on it exactly, or a save would duplicate the heading it meant to replace.
    public static let heading = "## Transcript"

    /// Separates `body` into the untouched text above the transcript heading and the
    /// segments below it. When there is no heading at all — every meeting before this phase's
    /// transcript ever gets written — the whole body is preamble and `segments` is empty.
    public static func split(_ body: String) -> (preamble: String, segments: [TranscriptSegment]) {
        guard let range = body.range(of: heading) else {
            return (body, [])
        }
        let preamble = String(body[body.startIndex..<range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let transcriptText = String(body[range.upperBound...])

        var segments: [TranscriptSegment] = []
        for rawLine in transcriptText.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, let segment = parseLine(line) else { continue }
            segments.append(segment)
        }
        return (preamble, segments)
    }

    /// Parses one `**Speaker** (timestamp) text` line by hand rather than with a regular
    /// expression — the shape is fixed and narrow enough that scanning for the three
    /// delimiters directly is no harder to follow than a pattern with four numbered capture
    /// groups would be, and it sidesteps needing a force-unwrapped or force-tried regex for
    /// what is, either way, a compile-time-fixed pattern.
    private static func parseLine(_ line: String) -> TranscriptSegment? {
        guard line.hasPrefix("**") else { return nil }
        let afterOpeningStars = line.index(line.startIndex, offsetBy: 2)
        guard
            let closingStars = line.range(
                of: "**", range: afterOpeningStars..<line.endIndex)
        else { return nil }
        let speaker = String(line[afterOpeningStars..<closingStars.lowerBound])
        guard !speaker.isEmpty else { return nil }

        var rest = line[closingStars.upperBound...]
        guard rest.hasPrefix(" (") else { return nil }
        rest = rest.dropFirst(2)
        guard let closingParen = rest.firstIndex(of: ")"),
            let offset = parseTimestamp(String(rest[rest.startIndex..<closingParen]))
        else { return nil }

        let afterTimestamp = rest[rest.index(after: closingParen)...]
        guard afterTimestamp.hasPrefix(" ") else { return nil }
        let text = afterTimestamp.dropFirst()

        return TranscriptSegment(
            speaker: speaker, offsetSeconds: offset, text: unescape(String(text)))
    }

    /// Rebuilds a full body from a preamble and its segments, in the shape ``split`` expects
    /// back. Omits the heading entirely when there are no segments, so a meeting with no
    /// transcript yet writes no dangling "## Transcript" with nothing under it.
    public static func join(preamble: String, segments: [TranscriptSegment]) -> String {
        let trimmedPreamble = preamble.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segments.isEmpty else { return trimmedPreamble }

        let lines = segments.map { segment in
            "**\(segment.speaker)** (\(formatTimestamp(seconds: segment.offsetSeconds))) "
                + escape(segment.text)
        }
        let transcript = "\(heading)\n\n" + lines.joined(separator: "\n")

        return trimmedPreamble.isEmpty ? transcript : "\(trimmedPreamble)\n\n\(transcript)"
    }

    // MARK: Timestamps

    /// `90` → `"01:30"`, `3_725` → `"1:02:05"`. Shared with ``Meeting/formattedDuration`` so
    /// a meeting's length and its transcript's offsets read in the same units.
    public static func formatTimestamp(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// Parses `"MM:SS"` or `"H:MM:SS"` back into seconds, or `nil` for anything else —
    /// including an empty string, so a stray `()` in hand-edited text is skipped as an
    /// unparseable line rather than read as a zero-second timestamp.
    private static func parseTimestamp(_ raw: String) -> Int? {
        let parts = raw.split(separator: ":")
        guard (2...3).contains(parts.count) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else { return nil }

        if numbers.count == 3 {
            return numbers[0] * 3600 + numbers[1] * 60 + numbers[2]
        }
        return numbers[0] * 60 + numbers[1]
    }

    // MARK: Escaping

    /// Only a literal newline threatens the one-line-per-segment shape, so only it (and the
    /// backslash that would otherwise make an escaped newline ambiguous with a real one) is
    /// escaped — `**` and parentheses inside an utterance are already unambiguous, per the
    /// type's doc comment, and escaping them too would just make the file harder to read by
    /// hand for no gain.
    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func unescape(_ text: String) -> String {
        var result = ""
        var iterator = text.makeIterator()
        while let character = iterator.next() {
            guard character == "\\" else {
                result.append(character)
                continue
            }
            switch iterator.next() {
            case "n": result.append("\n")
            case "\\": result.append("\\")
            case .some(let other):
                result.append("\\")
                result.append(other)
            case nil: result.append("\\")
            }
        }
        return result
    }
}
