import SwiftUI

/// The app's Settings window — reached from the app menu, like every macOS app's Settings.
/// The only thing to configure today is the two prompt templates the local LLM follows for
/// transcript cleanup and meeting summarization: this is what "the user can tweak them" (the
/// reason those templates live in the vault as plain markdown rather than hardcoded Swift
/// strings) looks like without needing to leave the app to open a text editor.
///
/// Saves as you type, the same way every other macOS Settings window applies a change
/// immediately rather than waiting for a Save button — these are prose instructions, not a
/// structured record with an invalid intermediate state to protect against, so there's nothing
/// an explicit save step would guard.
public struct PromptSettingsView: View {
    @Environment(VaultStore.self) private var store

    @State private var cleanupText = ""
    @State private var summaryText = ""

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                Text("Prompts")
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.textNormal)
                Text(
                    "Instructions the on-device model follows after a meeting is transcribed. "
                        + "Edits apply to the next meeting, not to transcripts already written."
                )
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textMuted)

                Card {
                    NotesField(
                        text: $cleanupText, title: "Transcript Cleanup",
                        placeholder: "How the model should tidy up a raw transcript…", height: 200
                    )
                    .onChange(of: cleanupText) { _, newValue in
                        save(.cleanup, text: newValue)
                    }
                }

                Card {
                    NotesField(
                        text: $summaryText, title: "Meeting Summary",
                        placeholder: "How the model should summarize a meeting…", height: 200
                    )
                    .onChange(of: summaryText) { _, newValue in
                        save(.summary, text: newValue)
                    }
                }
            }
            .padding(Theme.Spacing.xl)
        }
        .frame(width: 520, height: 560)
        .onAppear {
            cleanupText = PromptTemplateStore.load(.cleanup, location: store.location)
            summaryText = PromptTemplateStore.load(.summary, location: store.location)
        }
    }

    /// Best-effort, matching ``PromptTemplateStore``'s own seeding write: a failure here (a
    /// read-only vault) leaves the edit visible in this window for the rest of the session, just
    /// not persisted — the same posture the loader already takes, not a new one invented here.
    private func save(_ template: PromptTemplate, text: String) {
        try? PromptTemplateStore.save(template, text: text, location: store.location)
    }
}
