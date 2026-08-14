import SwiftUI

/// Jump-to-anything, in the spirit of Obsidian's quick switcher. Opened from Edit ▸ Jump to
/// Anything; the app declares no key equivalents.
///
/// Matching is a subsequence test rather than a substring one, so "mdp" finds
/// "Marie Dupont". Results are ranked so tighter matches float to the top.
struct CommandPalette: View {
    @Environment(VaultStore.self) private var store
    @Binding var isPresented: Bool
    @Binding var selection: EntityID?
    @Binding var editorRequest: EditorRequest?

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            field
            Divider().overlay(Theme.border)
            results
        }
        .frame(width: 520)
        .background(Theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.large)
                .stroke(Theme.borderStrong, lineWidth: Theme.hairline)
        )
        .onAppear { isFieldFocused = true }
        .onChange(of: query) { highlighted = 0 }
    }

    private var field: some View {
        HStack(spacing: Theme.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textFaint)
            TextField("", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.Font.paletteQuery)
                .foregroundStyle(Theme.textNormal)
                .placeholder(
                    "Jump to a person, organization, project or meeting…",
                    isVisible: query.isEmpty, font: Theme.Font.paletteQuery
                )
                .focused($isFieldFocused)
                .onSubmit { activate(at: highlighted) }
                // Arrow keys move the highlight; the text field keeps focus so typing
                // continues to filter.
                .onKeyPress(.upArrow) {
                    move(-1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    move(1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    isPresented = false
                    return .handled
                }
        }
        .padding(Theme.Spacing.medium)
        .textCursor()
    }

    @ViewBuilder
    private var results: some View {
        let items = results(for: query)
        if items.isEmpty {
            VStack(spacing: Theme.Spacing.xs) {
                Text("No matches")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textMuted)
                // Names the route that exists. It used to say "Press ⌘N", which stopped being
                // true when the app's key equivalents were removed.
                Text("Add one with the + beside PEOPLE, or the File menu.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textFaint)
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.large)
        } else {
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        row(item, isHighlighted: index == highlighted) {
                            activate(at: index)
                        }
                    }
                }
                .padding(Theme.Spacing.xs)
            }
            .frame(maxHeight: 320)
        }
    }

    private func row(_ item: Item, isHighlighted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.small) {
                EntityAvatar(
                    kind: item.kind, id: item.id,
                    size: Theme.Avatar.row,
                    isPlaceholder: item.isPlaceholder)

                Text(item.title)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textNormal)
                    .italic(item.isPlaceholder)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textFaint)
                }

                Spacer(minLength: 0)

                Text(item.kindLabel)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, Theme.Spacing.small)
            .padding(.vertical, 6)
            .background(isHighlighted ? Theme.accent.opacity(0.18) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickableCursor()
    }

    // MARK: Behaviour

    private func move(_ delta: Int) {
        let count = results(for: query).count
        guard count > 0 else { return }
        highlighted = min(max(highlighted + delta, 0), count - 1)
    }

    private func activate(at index: Int) {
        let items = results(for: query)
        guard items.indices.contains(index) else { return }
        selection = items[index].id
        isPresented = false
    }

    // MARK: Matching

    private struct Item: Identifiable {
        let id: EntityID
        let title: String
        let subtitle: String?
        /// The kind itself, not just its label: the row's avatar needs it to find the logo, and
        /// deriving the label from it keeps the two from drifting.
        let kind: EntityKind
        let isPlaceholder: Bool
        let score: Int

        var kindLabel: String { kind.displayName }
    }

    private func results(for query: String) -> [Item] {
        let needle = query.trimmingCharacters(in: .whitespaces)

        let candidates: [Item] = store.allEntities.compactMap { entity in
            let person = entity.asPerson
            // The role is the more useful hint of the two — "Head of Engineering" tells you
            // which Marie this is; the email usually just repeats the name.
            let subtitle = person?.role ?? person?.email
            // Search across the name, the id, the role and the email so any of them get you there.
            let haystacks = [
                entity.displayName, entity.id, person?.role ?? "", person?.email ?? "",
            ]

            let score: Int?
            if needle.isEmpty {
                score = 0
            } else {
                score = haystacks.compactMap { fuzzyScore(needle: needle, haystack: $0) }.max()
            }
            guard let score else { return nil }

            return Item(
                id: entity.id,
                title: entity.displayName,
                subtitle: subtitle,
                kind: entity.kind,
                isPlaceholder: person?.placeholder == true,
                score: score)
        }

        return Array(
            candidates
                .sorted {
                    $0.score != $1.score
                        ? $0.score > $1.score
                        : $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                .prefix(30)
        )
    }

    /// Subsequence match with a score, or `nil` if the needle doesn't fit.
    ///
    /// Consecutive characters and matches at word starts score higher, which is what
    /// makes "mdp" rank "Marie Dupont" above an incidental match elsewhere.
    private func fuzzyScore(needle: String, haystack: String) -> Int? {
        let target = Array(haystack.lowercased())
        let pattern = Array(needle.lowercased().filter { !$0.isWhitespace })
        guard !pattern.isEmpty else { return 0 }

        var score = 0
        var targetIndex = 0
        var lastMatch = -2

        for character in pattern {
            var found = false
            while targetIndex < target.count {
                if target[targetIndex] == character {
                    score += 1
                    if targetIndex == lastMatch + 1 { score += 3 }
                    if targetIndex == 0 || target[targetIndex - 1] == " "
                        || target[targetIndex - 1] == "-"
                    {
                        score += 5
                    }
                    lastMatch = targetIndex
                    targetIndex += 1
                    found = true
                    break
                }
                targetIndex += 1
            }
            guard found else { return nil }
        }

        // Prefer shorter targets: a match filling most of the name is a better hit.
        return score + max(0, 12 - target.count / 2)
    }
}
