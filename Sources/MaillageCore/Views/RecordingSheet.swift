import SwiftUI

/// Sets up and runs one recording: who it's with, then Start, then Stop.
///
/// Two phases in one sheet rather than a settings form that hands off to a separate recording
/// screen, because the fields on the first phase — mostly attendees — stay relevant and stay
/// editable on the second. Title, organization and project lock once recording starts. There is
/// no language field here at all — the transcription phase detects it from the audio itself,
/// once, from a dedicated pass — so nothing about it needs asking or locking up front.
///
/// This sheet *is* the "you are being recorded" indicator the design doc requires: it cannot
/// be swiped or Esc'd away while `isRecording`, only stopped, so there is no way to be
/// recording with nothing on screen saying so. `recorder` is a binding into `RootView`'s state,
/// not owned here — Stop & Save dismisses this sheet immediately, but transcription keeps
/// running in the background well after, so the recorder driving it must outlive the sheet.
struct RecordingSheet: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @Binding var recorder: MeetingRecorder?
    var onSaved: (EntityID) -> Void = { _ in }

    @State private var title = ""
    @State private var organizations: Set<EntityID> = []
    @State private var projects: Set<EntityID> = []
    @State private var attendees: Set<EntityID> = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            Text(isRecording ? "Recording…" : "New meeting")
                .font(Theme.Font.heading)
                .foregroundStyle(Theme.textNormal)

            if isRecording {
                recordingStatus
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                FormField("Title", placeholder: "Acme standup", text: $title)
                    .disabled(isRecording)

                MultiSelectField(
                    label: "Organization",
                    options: store.allOrganizations.map { ($0.id, $0.displayName) },
                    selected: $organizations,
                    kind: .organization,
                    prompt: "Search organizations",
                    limit: 1
                )
                .disabled(isRecording)

                MultiSelectField(
                    label: "Project",
                    options: store.allProjects.map { ($0.id, $0.displayName) },
                    selected: $projects,
                    kind: .project,
                    prompt: "Search projects",
                    limit: 1
                )
                .disabled(isRecording)

                // Never disabled: this is the one field the design doc calls out as staying
                // editable for the whole recording, since attendees are who's added as they
                // actually join.
                MultiSelectField(
                    label: "Attendees",
                    options: store.allPeople.map { ($0.id, $0.displayName) },
                    selected: $attendees,
                    kind: .person,
                    prompt: "Search people")
            }
            .opacity(isRecording ? 0.6 : 1)

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.projectColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            footer
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 460)
        .background(Theme.bgSecondary)
        .interactiveDismissDisabled(isRecording)
        .onChange(of: attendees) { _, newValue in syncAttendeesWhileRecording(newValue) }
        // A safety net, not the primary route to stopping: if the sheet is somehow torn down
        // while recording (a window close, not just this view's own Cancel/Stop), capture
        // must not keep writing to files nobody can reach anymore.
        .onDisappear { recorder?.stop() }
    }

    // MARK: Recording status

    private var recordingStatus: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack(spacing: Theme.Spacing.small) {
                Circle()
                    .fill(Theme.projectColor)
                    .frame(width: 8, height: 8)
                Text(TranscriptCodec.formatTimestamp(seconds: Int(elapsedSeconds)))
                    .font(Theme.Font.mono)
                    .foregroundStyle(Theme.textNormal)
                Spacer(minLength: 0)
            }
            levelMeter("You", level: recorder?.capture.microphoneLevel ?? 0)
            levelMeter("Them", level: recorder?.capture.systemAudioLevel ?? 0)
        }
        .padding(Theme.Spacing.medium)
        .background(Theme.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
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

    // MARK: Footer

    private var footer: some View {
        HStack {
            Spacer()
            if isRecording {
                PrimaryButton("Stop & Save", action: stopRecording)
            } else {
                SecondaryButton("Cancel") { dismiss() }
                PrimaryButton(
                    "Start Recording", isEnabled: title.nilIfBlank != nil, action: startRecording)
            }
        }
    }

    // MARK: Behaviour

    private var isRecording: Bool {
        recorder?.state == .recording
    }

    private var elapsedSeconds: TimeInterval {
        recorder?.capture.elapsedSeconds ?? 0
    }

    private func startRecording() {
        errorMessage = nil
        let newRecorder = MeetingRecorder(store: store)
        recorder = newRecorder
        Task {
            await newRecorder.start(
                title: title,
                organization: organizations.min().map(Wikilink.init),
                project: projects.min().map(Wikilink.init),
                attendees: attendees.sorted().map(Wikilink.init))
            if case .failed(let message) = newRecorder.state {
                errorMessage = message
            }
        }
    }

    private func stopRecording() {
        guard let recorder, let meetingID = recorder.meetingID else { return }
        recorder.stop()
        onSaved(meetingID)
        dismiss()
    }

    /// Attendees are the one field that stays live, so every change while recording is
    /// written straight to the meeting rather than waiting for a Save this sheet doesn't have.
    private func syncAttendeesWhileRecording(_ newValue: Set<EntityID>) {
        guard isRecording, let meetingID = recorder?.meetingID,
            var meeting = store.snapshot.meetings[meetingID]
        else { return }
        meeting.attendees = newValue.sorted().map(Wikilink.init)
        store.update(meeting)
    }
}
