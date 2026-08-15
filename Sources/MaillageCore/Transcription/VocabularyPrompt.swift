import Foundation

/// Builds the meeting-scoped prompt that biases WhisperKit's spelling of names and jargon.
///
/// Rendered as prose in the meeting's detected base language, never a bare word list — a
/// language-mismatched or list-shaped prompt can flip Whisper's decoder into the wrong language
/// or into translating, per the design doc's Constraint 2. Truncation is silent inside WhisperKit
/// itself, so the order terms are added in is the whole safeguard: drop jargon before dropping a
/// colleague's name.
public enum VocabularyPrompt {
    /// How many tokens the rendered prompt may spend, and how to measure it — bundled together
    /// since neither means anything without the other. WhisperKit's real tokenizer in
    /// production; a fake counter with a low `limit` in tests, to exercise truncation without a
    /// model.
    public struct TokenBudget {
        public let limit: Int
        public let count: (String) -> Int

        public init(limit: Int, count: @escaping (String) -> Int) {
            self.limit = limit
            self.count = count
        }
    }

    /// - Parameters:
    ///   - meeting: The meeting being transcribed, for its attendees, organization and project.
    ///   - snapshot: Resolves those wikilinks to display names.
    ///   - language: The language `LanguageDetector` found, e.g. `"fr"`. Selects the carrier
    ///     template; falls back to English for anything without one.
    ///   - customTerms: Already-prioritized extra vocabulary — usually
    ///     `VaultStore.usedProjectRoles + usedRelationLabels`, plus `.maillage/vocabulary.txt`,
    ///     in that order. This type doesn't know where they came from, only that they're last
    ///     in priority.
    /// - Returns: A natural-language sentence in `language`'s carrier template, or `""` if
    ///   nothing fits — never a truncated fragment.
    public static func build(
        meeting: Meeting,
        snapshot: VaultSnapshot,
        language: String?,
        customTerms: [String],
        budget: TokenBudget
    ) -> String {
        guard budget.limit > 0 else { return "" }

        let attendeeNames = meeting.attendees.map { snapshot.people[$0.id]?.displayName ?? $0.id }
        let organizationName = meeting.organization.flatMap {
            snapshot.organizations[$0.id]?.displayName
        }
        let projectName = meeting.project.flatMap { snapshot.projects[$0.id]?.displayName }
        let carrier = Carrier.template(for: language)

        // Priority order is the safeguard: keep adding terms while the rendered sentence still
        // fits, in the order a dropped term costs least — jargon before a colleague's name.
        var fittingTermCount = customTerms.count
        while fittingTermCount >= 0 {
            let candidateTerms = Array(customTerms.prefix(fittingTermCount))
            let sentence = carrier.render(
                attendeeNames: attendeeNames, organizationName: organizationName,
                projectName: projectName, terms: candidateTerms)
            if sentence.isEmpty || budget.count(sentence) <= budget.limit {
                return sentence
            }
            fittingTermCount -= 1
        }

        // Every term dropped and it still doesn't fit — the attendee/org/project clause alone
        // is over budget. Dropping those next would defeat the whole priority order, so give up
        // rather than truncate mid-name.
        let bare = carrier.render(
            attendeeNames: attendeeNames, organizationName: organizationName,
            projectName: projectName, terms: [])
        return budget.count(bare) <= budget.limit ? bare : ""
    }

    /// A per-language sentence shape. Prose, not a list — see Constraint 2.
    private struct Carrier {
        let opening: String
        let withOrganization: (String) -> String
        let withProject: (String) -> String
        let termsClause: ([String]) -> String
        let and: String

        static func template(for language: String?) -> Carrier {
            switch language {
            case "fr": return french
            default: return english
            }
        }

        func render(
            attendeeNames: [String], organizationName: String?, projectName: String?,
            terms: [String]
        ) -> String {
            var sentence = ""
            if !attendeeNames.isEmpty {
                sentence = "\(opening) \(joined(attendeeNames))"
                if let organizationName { sentence += withOrganization(organizationName) }
                if let projectName { sentence += withProject(projectName) }
                sentence += "."
            } else if let organizationName {
                sentence = "\(opening) \(organizationName)"
                if let projectName { sentence += withProject(projectName) }
                sentence += "."
            } else if let projectName {
                sentence = withProject(projectName).trimmingCharacters(in: .whitespaces) + "."
            }
            if !terms.isEmpty {
                let clause = termsClause(terms)
                sentence = sentence.isEmpty ? clause : "\(sentence) \(clause)"
            }
            return sentence
        }

        private func joined(_ names: [String]) -> String {
            guard let last = names.last else { return "" }
            guard names.count > 1 else { return last }
            return "\(names.dropLast().joined(separator: ", ")) \(and) \(last)"
        }

        private static let french = Carrier(
            opening: "Réunion avec",
            withOrganization: { " chez \($0)" },
            withProject: { ", projet \($0)" },
            termsClause: { "On parle de \($0.joined(separator: ", "))." },
            and: "et"
        )

        private static let english = Carrier(
            opening: "Meeting with",
            withOrganization: { " at \($0)" },
            withProject: { ", project \($0)" },
            termsClause: { "Terms used: \($0.joined(separator: ", "))." },
            and: "and"
        )
    }
}
