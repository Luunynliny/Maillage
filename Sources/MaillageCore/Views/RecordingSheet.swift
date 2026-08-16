import SwiftUI

/// The one thing this sheet does: take a title, then hand off to a recording.
///
/// Nothing else is asked here. Organization, project and attendees all moved to
/// ``MeetingView`` — once a meeting exists, that's the view you're already looking at, and it's
/// where the transcript will grow, so editing who/what a meeting is with belongs beside it, not
/// in a popup you can't see while reading. This sheet's only job is the one thing that has to
/// happen before a meeting exists at all: a title. The moment Start Recording succeeds, this
/// dismisses and the app jumps straight to that meeting's `MeetingView` — the recording banner
/// there, not this sheet, is what stays on screen for the rest of the recording.
///
/// `recorder` is a binding into `RootView`'s state, not owned here, since the recorder's
/// lifetime must outlive this sheet closing — see `MeetingRecorder`'s own doc comment for why.
struct RecordingSheet: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @Binding var recorder: MeetingRecorder?
    var onStarted: (EntityID) -> Void = { _ in }

    @State private var title = ""
    @State private var moreThanFourSpeakers = false
    @State private var isStarting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            Text("New meeting")
                .font(Theme.Font.heading)
                .foregroundStyle(Theme.textNormal)

            FormField("Title", placeholder: "Acme standup", text: $title)
                .disabled(isStarting)

            ToggleField(
                "More than 4 speakers?",
                caption:
                    "More than 4 people speaking through one microphone, or on one call? The "
                    + "on-device voice model can only tell 4 voices apart per audio source.",
                isOn: $moreThanFourSpeakers
            )
            .disabled(isStarting)

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
        .interactiveDismissDisabled(isStarting)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Spacer()
            SecondaryButton("Cancel") { dismiss() }
                .disabled(isStarting)
            PrimaryButton(
                isStarting ? "Starting…" : "Start Recording",
                isEnabled: !isStarting && title.nilIfBlank != nil,
                action: startRecording)
        }
    }

    // MARK: Behaviour

    private func startRecording() {
        errorMessage = nil
        isStarting = true
        let newRecorder = MeetingRecorder(store: store)
        recorder = newRecorder
        Task {
            await newRecorder.start(
                title: title, organization: nil, project: nil, attendees: [],
                disableDiarization: moreThanFourSpeakers)
            isStarting = false
            if let meetingID = newRecorder.meetingID {
                onStarted(meetingID)
                dismiss()
            } else if case .failed(let message) = newRecorder.state {
                errorMessage = message
            }
        }
    }
}
