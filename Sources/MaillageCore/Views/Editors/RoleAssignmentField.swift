import SwiftUI

/// Picks entities and gives each a role, for the two ends of project membership.
///
/// Search-first like ``MultiSelectField``, but a pick becomes a row rather than a pill,
/// because it carries a second field. Roles are held as a plain `[EntityID: String]` the
/// caller owns, so nothing is written until the sheet is saved — a half-filled roster in an
/// unsaved editor must not reach the vault.
struct RoleAssignmentField: View {
    /// Everything pickable, in display order.
    let options: [(id: EntityID, title: String, isPlaceholder: Bool)]
    /// What is being picked — one kind per field, since a project is staffed with people and a
    /// person is assigned projects. Drives both the pills' colour and each row's avatar.
    let kind: EntityKind
    let label: String
    let prompt: String
    /// Shown in place of the control when there is nothing to pick.
    let emptyMessage: String
    @Binding var selected: Set<EntityID>
    /// Role per entity. Entries for unselected ids are kept, so removing something and
    /// adding it back keeps the role it had.
    @Binding var roles: [EntityID: String]

    @State private var search = ""
    @State private var isSearchFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            // The role column gets its own header, since an empty input beside a name says
            // nothing about what goes in it. Only once there are rows to head, and pinned to
            // the same width as the field below so the two stay aligned.
            HStack(spacing: Theme.Spacing.small) {
                Text(label)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textMuted)

                if !selectedOptions.isEmpty {
                    Spacer(minLength: 0)
                    Text("Role")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: Theme.Width.roleField, alignment: .leading)
                        // Matches the field's own horizontal padding, so the header sits
                        // over the text it labels rather than over the box's edge.
                        .padding(.horizontal, Theme.Spacing.small)
                }
            }

            if options.isEmpty {
                Text(emptyMessage)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textFaint)
            } else {
                if !selectedOptions.isEmpty {
                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(selectedOptions, id: \.id) { option in
                            row(option)
                        }
                    }
                }

                SearchField(
                    prompt,
                    text: $search,
                    isFocused: $isSearchFocused,
                    onSubmit: addFirstMatch)

                if isSearchFocused || !search.isEmpty {
                    optionList
                }
            }
        }
    }

    /// One pick: what it is, the role on it, and a way off the list.
    private func row(_ option: (id: EntityID, title: String, isPlaceholder: Bool))
        -> some View
    {
        HStack(spacing: Theme.Spacing.small) {
            Pill(option.title, color: colour(option), icon: "xmark") {
                selected.remove(option.id)
            }

            Spacer(minLength: 0)

            RoleField(
                role: Binding(
                    get: { roles[option.id] ?? "" },
                    set: { roles[option.id] = $0 }))
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
                            isSelected: false,
                            isPlaceholder: option.isPlaceholder
                        ) {
                            selected.insert(option.id)
                            search = ""
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

    /// In `options` order, so rows don't reshuffle as roles are typed.
    private var selectedOptions: [(id: EntityID, title: String, isPlaceholder: Bool)] {
        options.filter { selected.contains($0.id) }
    }

    private var matches: [(id: EntityID, title: String, isPlaceholder: Bool)] {
        options.filter {
            !selected.contains($0.id)
                && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))
        }
    }

    /// A placeholder person stays desaturated, as ``Theme/color(for:)-(Person)`` does — the pill
    /// is the only place that distinction survived once the colour left the tuple.
    private func colour(_ option: (id: EntityID, title: String, isPlaceholder: Bool)) -> Color {
        option.isPlaceholder ? Theme.placeholderColor : Theme.color(for: kind)
    }

    private func addFirstMatch() {
        guard let first = matches.first else { return }
        selected.insert(first.id)
        search = ""
    }
}

/// Staffs a project from the project's side.
struct ParticipantsField: View {
    let people: [Person]
    @Binding var selected: Set<EntityID>
    @Binding var roles: [EntityID: String]

    var body: some View {
        RoleAssignmentField(
            options: people.map { ($0.id, $0.displayName, $0.placeholder) },
            kind: .person,
            label: "People",
            prompt: "Search people",
            emptyMessage: "No people in the vault yet — add some and you can staff this here.",
            selected: $selected,
            roles: $roles)
    }
}

/// The same memberships from the person's side.
struct ProjectMembershipsField: View {
    let projects: [Project]
    @Binding var selected: Set<EntityID>
    @Binding var roles: [EntityID: String]

    var body: some View {
        RoleAssignmentField(
            options: projects.map { ($0.id, $0.displayName, false) },
            kind: .project,
            label: "Projects",
            prompt: "Search projects",
            emptyMessage: "No projects in the vault yet.",
            selected: $selected,
            roles: $roles)
    }
}
