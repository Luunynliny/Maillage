import Foundation

/// Splits and joins the "## Transcript" section of a ``Meeting``'s markdown body.
///
/// Mirrors ``FrontmatterCodec``'s job one level down: that type separates the YAML header
/// from the body, this one separates the body's opaque preamble (an eventual "## Summary"
/// section, written by a later phase) from the one part of the body this type actually
/// understands. The preamble round-trips byte-for-byte, exactly like a person's notes do.
///
/// One line per segment: a timestamp, then the utterance.
/// ```
/// (00:15) Oui, mais il faut wire le canary d'abord.
/// ```
/// A meeting recorded while this vault still diarized speakers may have a `#M2` or
/// `#M2:marie-dupont` speaker tag after the timestamp, inside the same parens — ``parseSpeakerTag``
/// still parses that shape so an old file loads without a parse error, but nothing here writes it
/// back out or carries it into memory: diarization is gone, and a stale tag is just a second,
/// ignored token on the line, the same backward-compat story as the retired `organizations:`
/// frontmatter key.
///
/// The timestamp is `MM:SS`, or `H:MM:SS` once the offset reaches an hour — see
/// ``formatTimestamp(seconds:)``. The utterance itself is captured to the end of the line, so a
/// literal `(` or `)` inside it — someone saying a parenthetical — needs no escaping. A literal
/// newline inside an utterance is escaped to `\n` on the way out and restored on the way in,
/// which is the one thing that *would* otherwise break the one-line shape.
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

    /// Parses one `(timestamp [speakerTag]) text` line by hand rather than with a regular
    /// expression — the shape is fixed and narrow enough that scanning for the delimiters
    /// directly is no harder to follow than a pattern with numbered capture groups would be, and
    /// it sidesteps needing a force-unwrapped or force-tried regex for what is, either way, a
    /// compile-time-fixed pattern.
    private static func parseLine(_ line: String) -> TranscriptSegment? {
        guard line.hasPrefix("(") else { return nil }
        let afterOpenParen = line.index(after: line.startIndex)
        guard let closingParen = line[afterOpenParen...].firstIndex(of: ")") else { return nil }

        // The timestamp is always the first token; a leftover speaker tag from a meeting
        // diarized before this feature was removed, if present, is the second, space-separated
        // — so split on whitespace before parsing either, rather than handing the whole parens
        // content to `parseTimestamp`, which only ever expects one token. `parseSpeakerTag` is
        // called only to confirm the second token really is a stale tag and not something else
        // hand-typed; its result is discarded either way.
        let parensContent = line[afterOpenParen..<closingParen]
        let tokens = parensContent.split(separator: " ", maxSplits: 1)
        guard let firstToken = tokens.first, let offset = parseTimestamp(String(firstToken))
        else { return nil }
        if tokens.count > 1 { _ = parseSpeakerTag(String(tokens[1])) }

        let afterTimestamp = line[line.index(after: closingParen)...]
        guard afterTimestamp.hasPrefix(" ") else { return nil }
        let text = afterTimestamp.dropFirst()

        return TranscriptSegment(offsetSeconds: offset, text: unescape(String(text)))
    }

    /// Rebuilds a full body from a preamble and its segments, in the shape ``split`` expects
    /// back. Omits the heading entirely when there are no segments, so a meeting with no
    /// transcript yet writes no dangling "## Transcript" with nothing under it.
    public static func join(preamble: String, segments: [TranscriptSegment]) -> String {
        let trimmedPreamble = preamble.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segments.isEmpty else { return trimmedPreamble }

        let lines = segments.map { segment in
            let timestamp = formatTimestamp(seconds: segment.offsetSeconds)
            return "(\(timestamp)) " + escape(segment.text)
        }
        let transcript = "\(heading)\n\n" + lines.joined(separator: "\n")

        return trimmedPreamble.isEmpty ? transcript : "\(trimmedPreamble)\n\n\(transcript)"
    }

    // MARK: Speaker tags (backward compat only — nothing writes these anymore)

    /// Recognizes `#M2` or `#M2:marie-dupont` — a track letter, a slot digit, and an optional
    /// `:<personID>` — the speaker tag a meeting recorded before diarization was removed may
    /// still carry. Never called to build anything: only to confirm a line's second token is a
    /// stale tag and not some other hand-typed text, so `parseLine` can drop it and keep parsing
    /// the timestamp and text either way. No `Speaker` type exists anymore to parse it into.
    @discardableResult
    private static func parseSpeakerTag(_ raw: String) -> Bool {
        guard raw.hasPrefix("#") else { return false }
        let body = raw.dropFirst()

        let trackAndSlot: Substring
        if let colon = body.firstIndex(of: ":") {
            trackAndSlot = body[body.startIndex..<colon]
            guard !body[body.index(after: colon)...].isEmpty else { return false }
        } else {
            trackAndSlot = body
        }

        guard let trackLetter = trackAndSlot.first, trackLetter == "M" || trackLetter == "S"
        else { return false }
        return Int(trackAndSlot.dropFirst()) != nil
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
