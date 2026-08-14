import Foundation

/// One conversation: who was there, when, and what was said.
///
/// Unlike ``Person``/``Organization``/``Project``, nothing else links *to* a meeting —
/// attendance, like every other membership in this vault, lives on the side that has one
/// of something (here, one meeting has several attendees) rather than being duplicated
/// onto each person. So `attendees`, `organization` and `project` are read-only from a
/// meeting's own perspective: nobody's file gains a `meetings:` list when one is created.
public struct Meeting: Entity, Codable {
    public var id: EntityID
    public var title: String
    /// When the meeting happened. Optional so a malformed file still loads — ``VaultReader``
    /// treats a bad file as an issue, never a crash — but every meeting the app creates sets it.
    public var date: CalendarDay?
    /// Length of the recording in seconds, once transcription has run. `nil` until then.
    public var duration: Int?
    /// The base language `LanguageDetector` found in the recording, e.g. `fr`. `nil` until
    /// transcription has run; see ``VocabularyPrompt`` for how the detected language anchors
    /// the vocabulary prompt and the decoder for the rest of the meeting.
    public var language: String?
    /// The organization this meeting was held with, if any. Singular, like ``Person/organization``
    /// and ``Project/organization``: a meeting is with one company at a time.
    public var organization: Wikilink?
    /// The project this meeting was about, if any.
    public var project: Wikilink?
    /// Who was there. A flat list — added by hand while the meeting is happening, since this
    /// vault records no speaker identification.
    public var attendees: [Wikilink]
    public var created: CalendarDay?
    /// Holds the generated "## Summary" and "## Transcript" sections. ``TranscriptCodec``
    /// reads and writes the latter; the former is opaque text this type never parses.
    public var body: String

    public var kind: EntityKind { .meeting }

    /// Falls back to the id — a bare date-stamped slug — rather than to "Untitled meeting",
    /// so an incompletely seeded file still shows something that identifies *which* one it is.
    public var displayName: String { title.isEmpty ? id : title }

    /// `duration` as `MM:SS`/`H:MM:SS`, or `nil` before transcription has run. Shares
    /// ``TranscriptCodec/formatTimestamp(seconds:)`` with the transcript's own offsets, so a
    /// meeting's length and the timestamps inside it are never in different units.
    public var formattedDuration: String? {
        duration.map(TranscriptCodec.formatTimestamp)
    }

    public init(
        id: EntityID,
        title: String,
        date: CalendarDay? = nil,
        duration: Int? = nil,
        language: String? = nil,
        organization: Wikilink? = nil,
        project: Wikilink? = nil,
        attendees: [Wikilink] = [],
        created: CalendarDay? = nil,
        body: String = ""
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.duration = duration
        self.language = language
        self.organization = organization
        self.project = project
        self.attendees = attendees
        self.created = created
        self.body = body
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id, type, title, date, duration, language, organization, project, attendees, created
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(EntityID.self, forKey: .id)
        self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.date = try c.decodeIfPresent(CalendarDay.self, forKey: .date)
        self.duration = try c.decodeIfPresent(Int.self, forKey: .duration)
        self.language = try c.decodeIfPresent(String.self, forKey: .language)
        self.organization = try c.decodeIfPresent(Wikilink.self, forKey: .organization)
        self.project = try c.decodeIfPresent(Wikilink.self, forKey: .project)
        self.attendees = try c.decodeIfPresent([Wikilink].self, forKey: .attendees) ?? []
        self.created = try c.decodeIfPresent(CalendarDay.self, forKey: .created)
        self.body = ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(EntityKind.meeting.rawValue, forKey: .type)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(date, forKey: .date)
        try c.encodeIfPresent(duration, forKey: .duration)
        try c.encodeIfPresent(language, forKey: .language)
        try c.encodeIfPresent(organization, forKey: .organization)
        try c.encodeIfPresent(project, forKey: .project)
        if !attendees.isEmpty { try c.encode(attendees, forKey: .attendees) }
        try c.encodeIfPresent(created, forKey: .created)
    }
}

/// One utterance in a transcript: who said it, when, and what.
///
/// `speaker` is a free-text label (`"You"`, `"Marie Dupont"`, `"Them"`), not a ``Wikilink`` —
/// this vault records no speaker identification, so nothing here is guaranteed to resolve to
/// an attendee. Later phases may write a label that happens to match one, but ``TranscriptCodec``
/// treats it as text throughout.
public struct TranscriptSegment: Hashable, Sendable {
    public var speaker: String
    /// Offset from the start of the recording.
    public var offsetSeconds: Int
    public var text: String

    public init(speaker: String, offsetSeconds: Int, text: String) {
        self.speaker = speaker
        self.offsetSeconds = offsetSeconds
        self.text = text
    }
}
