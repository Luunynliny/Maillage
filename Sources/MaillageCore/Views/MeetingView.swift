import SwiftUI

/// A conversation, read top to bottom: who was there, the summary, then the transcript.
///
/// Not a graph or a roster like the other three subject views — there is no layout to
/// preserve, only an order things were said in — so this is the one place in the app that
/// scrolls a plain column rather than laying out a stack or a board.
///
/// The summary and the transcript are two different trust levels of the same body: the
/// transcript is what ``TranscriptCodec`` guarantees round-trips exactly, the summary is
/// whatever a later phase's model wrote above it and is shown as-is, unparsed, the same way
/// a person's notes are — plain text, not rendered markdown.
struct MeetingView: View {
    @Environment(VaultStore.self) private var store

    let meeting: Meeting
    @Binding var selection: EntityID?
    @Binding var editorRequest: EditorRequest?
    @Binding var isDetailVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            CenterPaneHeader(
                entity: .meeting(meeting), subtitle: subtitle,
                isDetailVisible: $isDetailVisible, selection: $selection,
                editorRequest: $editorRequest)

            if attendees.isEmpty && segments.isEmpty && preamble.isEmpty {
                EmptyStateView(
                    icon: "calendar",
                    title: "Nothing recorded yet",
                    message:
                        "\(meeting.displayName) has no attendees or transcript. Add either by editing the vault file directly for now."
                )
            } else {
                content
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                if !attendees.isEmpty {
                    attendeesSection
                }
                if !preamble.isEmpty {
                    summaryCard
                }
                if !segments.isEmpty {
                    transcriptSection
                }
            }
            .padding(Theme.Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Attendees

    /// Who was there, led by an ``EntityLink`` each rather than a ``Pill``: an attendee is a
    /// person you can click through to, and this is the pane a meeting's attendees are read
    /// from — the same reasoning that replaced pills with links everywhere else an entity is
    /// linked to, not just named.
    private var attendeesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            SectionHeader("Attendees", trailing: "\(attendees.count)")
            FlowLayout(spacing: Theme.Spacing.medium) {
                ForEach(attendees, id: \.id) { link in
                    EntityLink(
                        title: store.displayName(for: link.id) ?? link.id,
                        kind: .person,
                        id: link.id,
                        isPlaceholder: store.entity(id: link.id)?.asPerson?.placeholder == true
                    ) {
                        selection = link.id
                    }
                }
            }
        }
    }

    // MARK: Summary

    /// The preamble ``TranscriptCodec`` split off — an eventual "## Summary" section, written
    /// by a later phase. Shown as plain text, like a person's notes: it is generated prose to
    /// read, not a form to render fields from.
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            SectionHeader("Summary")
            Card {
                Text(preamble)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textNormal)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Transcript

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            SectionHeader("Transcript")
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    segmentRow(segment)
                }
            }
        }
    }

    /// `**Speaker** (00:15)` above the line, the words below — a transcript is read by
    /// scanning who's talking first, the same reason a chat app leads each bubble with a
    /// name. `speaker` is text, not a ``Wikilink``: this vault records no speaker
    /// identification, so nothing here is assumed to resolve to an attendee.
    private func segmentRow(_ segment: TranscriptSegment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(segment.speaker)
                    .font(Theme.Font.body.weight(.semibold))
                    .foregroundStyle(Theme.textNormal)
                Text(TranscriptCodec.formatTimestamp(seconds: segment.offsetSeconds))
                    .font(Theme.Font.mono)
                    .foregroundStyle(Theme.textFaint)
            }
            Text(segment.text)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textNormal)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Data

    private var attendees: [Wikilink] { meeting.attendees }

    private var preamble: String {
        TranscriptCodec.split(meeting.body).preamble
    }

    private var segments: [TranscriptSegment] {
        TranscriptCodec.split(meeting.body).segments
    }

    private var subtitle: String {
        let count = attendees.count
        let people = "\(count) \(count == 1 ? "attendee" : "attendees")"
        guard let date = meeting.date else { return people }
        return "\(people) · \(date.description)"
    }
}
