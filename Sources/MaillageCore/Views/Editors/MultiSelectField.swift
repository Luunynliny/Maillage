import SwiftUI

/// Picks entities, used for org and project membership.
///
/// Laying every option out as a pill stops scaling once a vault holds hundreds of
/// organizations, so this is search-first: what you've picked stays pinned as removable
/// pills, and the options list below only appears once you type or focus the field.
struct MultiSelectField: View {
    let label: String
    let options: [(id: EntityID, title: String)]
    @Binding var selected: Set<EntityID>
    /// What is being picked. Supplies the pills' colour *and* lets each option row show that
    /// entity's logo — one value instead of a colour, so the two can't disagree.
    let kind: EntityKind
    /// Shown under the search field when nothing is typed yet.
    var prompt: String = "Search to add"
    /// How many can be held at once, or `nil` for no ceiling.
    ///
    /// `1` makes this a single-select — picking replaces rather than adds, which is how a
    /// person's employer is chosen. Deliberately not a separate component: the search,
    /// pills and option list are identical, only the arity differs.
    var limit: Int?

    @State private var search = ""
    @State private var isSearchFocused = false

    var body: some View {
        if !options.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(label)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textMuted)

                if !selectedOptions.isEmpty {
                    FlowLayout(spacing: Theme.Spacing.xs) {
                        ForEach(selectedOptions, id: \.id) { option in
                            Pill(option.title, color: Theme.color(for: kind), icon: "xmark") {
                                selected.remove(option.id)
                            }
                        }
                    }
                }

                SearchField(
                    prompt,
                    text: $search,
                    isFocused: $isSearchFocused,
                    onSubmit: addFirstMatch)

                // Kept out of the way until asked for: an always-open list would push the
                // rest of the form down and make short vaults feel heavier than they are.
                if isSearchFocused || !search.isEmpty {
                    optionList
                }
            }
        }
    }

    private var optionList: some View {
        ScrollView {
            VStack(spacing: 1) {
                if matches.isEmpty {
                    Text("No matches")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.Spacing.small)
                        .padding(.vertical, 5)
                } else {
                    ForEach(matches, id: \.id) { option in
                        SidebarRow(
                            title: option.title,
                            kind: kind,
                            id: option.id,
                            isSelected: false
                        ) {
                            pick(option.id)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.xs)
        }
        .frame(maxHeight: 108)
        .background(Theme.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium)
                .stroke(Theme.border, lineWidth: Theme.hairline)
        )
    }

    /// Selected first, in the order the caller gave, so the pills don't reshuffle.
    private var selectedOptions: [(id: EntityID, title: String)] {
        options.filter { selected.contains($0.id) }
    }

    /// Anything not already picked that matches what's typed.
    private var matches: [(id: EntityID, title: String)] {
        options.filter {
            !selected.contains($0.id)
                && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))
        }
    }

    /// Return adds the top match, so a whole list can be built without the mouse.
    private func addFirstMatch() {
        guard let first = matches.first else { return }
        pick(first.id)
    }

    /// Adds `id`, making room by dropping earlier picks once ``limit`` is reached.
    ///
    /// Making room rather than refusing: at a limit of 1, clicking a second organization
    /// obviously means "this one instead", and a field that went inert until the first
    /// pill was dismissed would read as a bug.
    private func pick(_ id: EntityID) {
        if let limit, selected.count >= limit {
            let keep = selectedOptions.suffix(max(0, limit - 1)).map(\.id)
            selected = Set(keep)
        }
        selected.insert(id)
        search = ""
    }
}
