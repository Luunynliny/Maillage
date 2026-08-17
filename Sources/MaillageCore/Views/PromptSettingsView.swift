import AppKit
import SwiftUI

/// The app's Settings window — reached from the app menu, like every macOS app's Settings.
/// The only thing to configure today is the two prompt templates the local LLM follows for
/// transcript cleanup and meeting summarization: this is "the user can tweak them" (the reason
/// those templates live in the vault as plain markdown rather than hardcoded Swift strings) —
/// pointing at where each file lives and a button to open it in whatever the user already edits
/// text with, rather than a second, in-app editor for a plain text file that already has one.
public struct PromptSettingsView: View {
    @Environment(VaultStore.self) private var store

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            Text("Prompts")
                .font(Theme.Font.heading)
                .foregroundStyle(Theme.textNormal)
            Text(
                "Instructions the on-device model follows after a meeting is transcribed, kept "
                    + "as plain markdown files in your vault so you can edit them in any text "
                    + "editor. Edits apply to the next meeting, not to transcripts already written."
            )
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.textMuted)

            promptRow(.cleanup, title: "Transcript Cleanup")
            promptRow(.summary, title: "Meeting Summary")
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 480)
    }

    private func promptRow(_ template: PromptTemplate, title: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                Text(title)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textNormal)
                Text(url(for: template).path)
                    .font(Theme.Font.mono)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                SecondaryButton("Open") { open(template) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func url(for template: PromptTemplate) -> URL {
        store.location.promptURL(named: template.filename)
    }

    /// Seeds the file with its built-in default first if this is the first time anyone's asked
    /// for it — the same lazy-creation `PromptTemplateStore.load` already does before a meeting
    /// ever reads it, so "Open" always finds something rather than a blank/missing file.
    private func open(_ template: PromptTemplate) {
        _ = PromptTemplateStore.load(template, location: store.location)
        NSWorkspace.shared.open(url(for: template))
    }
}
