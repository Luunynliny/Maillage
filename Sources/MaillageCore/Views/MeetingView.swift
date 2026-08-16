import MarkdownUI
import SwiftUI

/// A conversation, read top to bottom: who was there, the summary, then the transcript.
///
/// Not a graph or a roster like the other three subject views — there is no layout to
/// preserve, only an order things were said in — so this is the one place in the app that
/// scrolls a plain column rather than laying out a stack or a board.
///
/// The summary and the transcript are two different trust levels of the same body: the
/// transcript is what ``TranscriptCodec`` guarantees round-trips exactly, the summary is
/// whatever a later phase's model wrote above it — headings, bullets, bold/italic emphasis
/// (see the design doc's `MeetingSummary` example) — and is rendered as markdown via
/// MarkdownUI rather than hand-parsed, the same as the vault file reads in Obsidian.
struct MeetingView: View {
    @Environment(VaultStore.self) private var store

    let meeting: Meeting
    @Binding var selection: EntityID?
    @Binding var editorRequest: EditorRequest?
    @Binding var isDetailVisible: Bool
    /// Whether *this* meeting is the one `RootView`'s recorder is currently working on — the
    /// only way to tell "nothing here yet because it's still transcribing" from "nothing here
    /// because nothing was ever added," which otherwise look identical.
    let activeRecorder: MeetingRecorder?

    /// Seeded from `meeting` once, at init, then only ever written to by the recording banner's
    /// own pickers — never read back from `meeting` afterward. That mirrors how the old
    /// `RecordingSheet` held these locally: this view calls `store.update` to push a change out,
    /// but the picker's own selection is what's on screen, not a reflection of the store. The
    /// caller must give this view a fresh identity per meeting (`.id(meeting.id)`) so switching
    /// between two meetings doesn't carry one's edits onto the other.
    @State private var selectedOrganizations: Set<EntityID>
    @State private var selectedProjects: Set<EntityID>
    @State private var selectedAttendees: Set<EntityID>

    init(
        meeting: Meeting, selection: Binding<EntityID?>, editorRequest: Binding<EditorRequest?>,
        isDetailVisible: Binding<Bool>, activeRecorder: MeetingRecorder?
    ) {
        self.meeting = meeting
        self._selection = selection
        self._editorRequest = editorRequest
        self._isDetailVisible = isDetailVisible
        self.activeRecorder = activeRecorder
        _selectedOrganizations = State(initialValue: meeting.organization.map { [$0.id] } ?? [])
        _selectedProjects = State(initialValue: meeting.project.map { [$0.id] } ?? [])
        _selectedAttendees = State(initialValue: Set(meeting.attendees.map(\.id)))
    }

    var body: some View {
        VStack(spacing: 0) {
            CenterPaneHeader(
                entity: .meeting(meeting), subtitle: subtitle,
                isDetailVisible: $isDetailVisible, selection: $selection,
                editorRequest: $editorRequest)

            if isRecordingThisMeeting || isTranscribing
                || !(attendees.isEmpty && segments.isEmpty && preamble.isEmpty)
            {
                content
            } else {
                EmptyStateView(
                    icon: "calendar",
                    title: "Nothing recorded yet",
                    message:
                        "\(meeting.displayName) has no attendees or transcript. Add either by editing the vault file directly for now."
                )
            }
        }
        .onChange(of: selectedOrganizations) { _, newValue in
            syncOrganizationWhileRecording(newValue)
        }
        .onChange(of: selectedProjects) { _, newValue in
            deriveOrganizationFromProject(newValue)
            syncProjectWhileRecording(newValue)
        }
        .onChange(of: selectedAttendees) { _, newValue in syncAttendeesWhileRecording(newValue) }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                if isRecordingThisMeeting {
                    recordingBanner
                }
                if !attendees.isEmpty, !isRecordingThisMeeting {
                    attendeesSection
                }
                if isTranscribing {
                    transcribingCard
                }
                if isSummarising {
                    summarisingCard
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

    // MARK: Recording

    /// This *is* the "you are being recorded" indicator the design doc requires — a French
    /// legal obligation, not only GDPR — now that starting a recording jumps straight here
    /// instead of leaving it behind a modal. As long as this meeting is the one recording,
    /// this banner is the first thing in the pane, above everything else, and it's the only
    /// place Stop & Save lives.
    private var recordingBanner: some View {
        Card {
            HStack(spacing: Theme.Spacing.small) {
                Circle()
                    .fill(Theme.projectColor)
                    .frame(width: 8, height: 8)
                Text("Recording…")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textNormal)
                Text(TranscriptCodec.formatTimestamp(seconds: Int(elapsedSeconds)))
                    .font(Theme.Font.mono)
                    .foregroundStyle(Theme.textMuted)
                Spacer(minLength: 0)
                PrimaryButton("Stop & Save") { activeRecorder?.stop() }
            }
            levelMeter("You", level: activeRecorder?.capture.microphoneLevel ?? 0)
            levelMeter("Them", level: activeRecorder?.capture.systemAudioLevel ?? 0)

            Divider()
                .padding(.vertical, Theme.Spacing.xs)

            MultiSelectField(
                label: "Organization",
                options: store.allOrganizations.map { ($0.id, $0.displayName) },
                selected: $selectedOrganizations,
                kind: .organization,
                prompt: "Search organizations",
                limit: 1
            )

            MultiSelectField(
                label: "Project",
                options: projectOptions,
                selected: $selectedProjects,
                kind: .project,
                prompt: "Search projects",
                limit: 1
            )

            MultiSelectField(
                label: "Attendees",
                options: store.allPeople.map { ($0.id, $0.displayName) },
                selected: $selectedAttendees,
                kind: .person,
                prompt: "Search people")
        }
    }

    /// A silent "Them" track is the most likely failure in the whole capture path — the
    /// system tap can fail in ways that don't throw — so this meter is the only place that
    /// failure is visible at all while it can still be fixed, rather than discovered later
    /// in an empty transcript.
    private func levelMeter(_ label: String, level: Float) -> some View {
        HStack(spacing: Theme.Spacing.small) {
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textMuted)
                .frame(width: 40, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Theme.Radius.small)
                        .fill(Theme.bgSecondary)
                    RoundedRectangle(cornerRadius: Theme.Radius.small)
                        .fill(Theme.accent)
                        .frame(width: geometry.size.width * CGFloat(min(level * 4, 1)))
                }
            }
            .frame(height: 6)
        }
    }

    private var isRecordingThisMeeting: Bool {
        activeRecorder?.meetingID == meeting.id && activeRecorder?.state == .recording
    }

    private var elapsedSeconds: TimeInterval {
        activeRecorder?.capture.elapsedSeconds ?? 0
    }

    /// Filtered to the chosen organization so a later project pick can never silently overwrite
    /// it — falls back to every project when no organization is set yet.
    private var projectOptions: [(EntityID, String)] {
        guard let organizationID = selectedOrganizations.first else {
            return store.allProjects.map { ($0.id, $0.displayName) }
        }
        return store.projects(inOrganization: organizationID).map { ($0.id, $0.displayName) }
    }

    /// Organization always follows the chosen project, never the other way around — a project
    /// belongs to exactly one organization, so picking one can't leave a mismatch to validate
    /// against. Clearing the project leaves the derived organization in place, since it's still
    /// meaningful on its own.
    private func deriveOrganizationFromProject(_ newValue: Set<EntityID>) {
        guard let projectID = newValue.first,
            let organization = store.allProjects.first(where: { $0.id == projectID })?.organization
        else { return }
        selectedOrganizations = [organization.id]
    }

    /// Organization, project and attendees all stay live, so every change while recording is
    /// written straight to the meeting rather than waiting for a Save this view doesn't have.
    private func syncOrganizationWhileRecording(_ newValue: Set<EntityID>) {
        guard isRecordingThisMeeting, var updated = store.snapshot.meetings[meeting.id] else {
            return
        }
        updated.organization = newValue.first.map(Wikilink.init)
        store.update(updated)
    }

    private func syncProjectWhileRecording(_ newValue: Set<EntityID>) {
        guard isRecordingThisMeeting, var updated = store.snapshot.meetings[meeting.id] else {
            return
        }
        updated.project = newValue.first.map(Wikilink.init)
        store.update(updated)
    }

    private func syncAttendeesWhileRecording(_ newValue: Set<EntityID>) {
        guard isRecordingThisMeeting, var updated = store.snapshot.meetings[meeting.id] else {
            return
        }
        updated.attendees = newValue.sorted().map(Wikilink.init)
        store.update(updated)
    }

    // MARK: Transcribing

    /// Covers the wait between Stop and a written transcript — the background pipeline
    /// `MeetingRecorder` kicks off on Stop, which outlives the recording sheet closing.
    /// `summarisingCard` below is the analogous spinner for the step right after this one.
    private var transcribingCard: some View {
        Card {
            HStack(spacing: Theme.Spacing.small) {
                ProgressView()
                    .controlSize(.small)
                Text("Transcribing…")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var isTranscribing: Bool {
        activeRecorder?.meetingID == meeting.id && activeRecorder?.state == .transcribing
    }

    // MARK: Summarising

    private var summarisingCard: some View {
        Card {
            HStack(spacing: Theme.Spacing.small) {
                ProgressView()
                    .controlSize(.small)
                Text("Summarising…")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var isSummarising: Bool {
        activeRecorder?.meetingID == meeting.id && activeRecorder?.state == .summarising
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
    /// by a later phase. `Markdown` is MarkdownUI's own block-plus-inline renderer, styled by
    /// ``MarkdownUI/Theme/maillage`` so it draws from ``Theme`` rather than the library's
    /// defaults.
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            SectionHeader("Summary")
            Card {
                Markdown(preamble)
                    .markdownTheme(.maillage)
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

    /// Timestamp above the words. No left/right alignment or other spatial stand-in for who's
    /// speaking: this vault records no speaker identification, so introducing one visually would
    /// just reintroduce the same false distinction in a different form.
    private func segmentRow(_ segment: TranscriptSegment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(TranscriptCodec.formatTimestamp(seconds: segment.offsetSeconds))
                .font(Theme.Font.mono)
                .foregroundStyle(Theme.textFaint)
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

extension MarkdownUI.Theme {
    /// MarkdownUI's block and inline styles, redirected to ``Theme`` tokens instead of the
    /// library's own defaults — the same reasoning as every other view in the app: reference
    /// ``Theme``, never a literal. One heading size: the design doc's generated summaries only
    /// ever use a single level (`### Decisions`), and ``Theme/Font`` only defines one heading
    /// style to begin with.
    static let maillage = MarkdownUI.Theme()
        .text {
            ForegroundColor(Theme.textNormal)
        }
        .strong {
            FontWeight(.semibold)
        }
        .emphasis {
            FontStyle(.italic)
        }
        .code {
            FontFamilyVariant(.monospaced)
        }
        .link {
            ForegroundColor(Theme.accent)
        }
        .heading1(body: headingBody)
        .heading2(body: headingBody)
        .heading3(body: headingBody)
        .heading4(body: headingBody)
        .heading5(body: headingBody)
        .heading6(body: headingBody)
        .paragraph { configuration in
            configuration.label
                .font(Theme.Font.body)
                .markdownMargin(top: .zero, bottom: Theme.Spacing.small)
        }
        .listItem { configuration in
            configuration.label
                .font(Theme.Font.body)
                .markdownMargin(top: Theme.Spacing.xs)
        }
        .bulletedListMarker { _ in
            Text("•")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textFaint)
        }

    private static func headingBody(_ configuration: BlockConfiguration) -> some View {
        configuration.label
            .font(Theme.Font.heading)
            .markdownMargin(top: Theme.Spacing.medium, bottom: Theme.Spacing.small)
    }
}
