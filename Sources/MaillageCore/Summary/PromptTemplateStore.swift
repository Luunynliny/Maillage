import Foundation

/// One of the two vault-level, user-editable prompt templates the local LLM uses. Kept as plain
/// markdown files under `.maillage/prompts/` rather than hardcoded Swift strings, so a user can
/// tune wording for their own meetings without touching code — see ``PromptTemplateStore``.
public enum PromptTemplate: Sendable {
    case cleanup
    case summary

    var filename: String {
        switch self {
        case .cleanup: "cleanup"
        case .summary: "summary"
        }
    }

    /// Deliberately basic — a reasonable starting point, not a finely-tuned prompt. Getting the
    /// wording right needs iteration against real recordings, which is a follow-up, not something
    /// this default tries to front-load.
    var defaultText: String {
        switch self {
        case .cleanup:
            """
            You clean up one excerpt of an automatically transcribed meeting. Remove sentences or \
            words that are hallucinated, nonsensical, or clearly don't belong (stock phrases like \
            "thank you" that don't fit the conversation, garbled fragments) by dropping them \
            entirely — never replace them with placeholder text. Fix obvious formatting and \
            punctuation. Do not summarize, shorten, or add anything — keep the speaker's actual \
            words as close to the original as possible aside from removing garbage.

            Respond with the same "(mm:ss) text" lines you were given, one per line, in the same \
            order, with only that cleanup applied. No commentary before or after the lines.
            """
        case .summary:
            """
            You summarize a meeting transcript in clear, concise markdown. Cover, in order: the \
            meeting's outcome, the notable points discussed, decisions reached, and concrete \
            follow-up actions with an owner. Use short "### " headings as needed and omit any \
            section that doesn't apply. Do not invent information the transcript doesn't contain.
            """
        }
    }
}

/// Loads a prompt template from the vault, seeding it with the built-in default the first time
/// it's needed if the vault doesn't already have one — so the file exists to edit right after the
/// very first meeting, with no separate setup step.
public enum PromptTemplateStore {
    public static func load(_ template: PromptTemplate, location: VaultLocation) -> String {
        let url = location.promptURL(named: template.filename)
        if let text = try? String(contentsOf: url, encoding: .utf8),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return text
        }
        // Best-effort seed: a write failure (e.g. a read-only vault) still leaves the built-in
        // default usable in memory for this run, just not saved for someone to edit next time.
        try? VaultWriter(location: location).writeAtomically(
            Data(template.defaultText.utf8), to: url)
        return template.defaultText
    }
}
