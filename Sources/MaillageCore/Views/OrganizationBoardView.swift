import SwiftUI

/// An organization's projects and who staffs each, as a board of cards.
///
/// Not a graph: org → projects → people is a containment hierarchy two levels deep, and
/// every edge in it would mean the same thing ("belongs to"), so position carries the
/// structure for free. Laid out rather than simulated, which also means it looks the same
/// every time you open it.
struct OrganizationBoardView: View {
    @Environment(VaultStore.self) private var store

    let organization: Organization
    @Binding var selection: EntityID?
    /// So the header can open the editor that changes it.
    @Binding var editorRequest: EditorRequest?
    /// Whether the header's details section is folded out. Owned by ``RootView``.
    @Binding var isDetailVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            CenterPaneHeader(
                entity: .organization(organization),
                subtitle: subtitle,
                isDetailVisible: $isDetailVisible,
                selection: $selection,
                editorRequest: $editorRequest)

            if projects.isEmpty && employees.isEmpty {
                EmptyStateView(
                    icon: "rectangle.stack",
                    title: "Nothing here yet",
                    message:
                        "Link people to \(organization.displayName) and give it a project or two, and its work will lay out here."
                )
            } else {
                board
            }
        }
    }

    private var board: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: Theme.Spacing.medium) {
                ForEach(projects) { project in
                    projectCard(project)
                }
                // Employees on none of this org's projects, so the board accounts for
                // everybody rather than quietly omitting them.
                if !unassigned.isEmpty {
                    unassignedCard
                }
            }
            .padding(Theme.Spacing.large)
        }
    }

    // MARK: Cards

    private func projectCard(_ project: Project) -> some View {
        let participants = store.participants(ofProject: project.id)
        // People on the project who work elsewhere: worth showing, and worth marking, so
        // an outside collaborator isn't mistaken for a colleague.
        let outsiders = Set(
            participants.filter { $0.person.organization?.id != organization.id }
                .map(\.person.id))

        return Card {
            Button {
                selection = project.id
            } label: {
                HStack(spacing: Theme.Spacing.small) {
                    EntityAvatar(
                        kind: .project, id: project.id, size: Theme.Avatar.card)
                    Text(project.displayName)
                        .font(Theme.Font.heading)
                        .foregroundStyle(Theme.textNormal)
                    Spacer(minLength: 0)
                    Text(project.status.displayName)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textFaint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .clickableCursor()

            if participants.isEmpty {
                Text("Nobody on it yet.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textFaint)
            } else {
                ForEach(participants, id: \.person.id) { participant in
                    memberRow(
                        participant.person,
                        role: participant.role,
                        isOutsider: outsiders.contains(participant.person.id))
                }
            }
        }
        .frame(width: 240)
    }

    private var unassignedCard: some View {
        Card {
            HStack(spacing: Theme.Spacing.small) {
                Circle()
                    .strokeBorder(Theme.textFaint, lineWidth: 1.5)
                    .frame(width: Theme.entityDot, height: Theme.entityDot)
                Text("On no project")
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.textMuted)
                Spacer(minLength: 0)
            }

            // No role line here on purpose. These people hold no role *on a project*, and
            // the profile role sits in the same slot the project cards use for one — so
            // showing "Dev" here would read as a project role rather than a job title.
            ForEach(unassigned) { person in
                memberRow(person, role: nil, isOutsider: false)
            }
        }
        .frame(width: 240)
    }

    /// One person on a card: their name, and the role they hold **on that project** if any.
    ///
    /// Only ever a project role. A person's `role` is their job title, which means something
    /// different, and putting the two in the same slot would make them indistinguishable.
    private func memberRow(_ person: Person, role: String?, isOutsider: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: Theme.Spacing.xs) {
                Pill(person.displayName, color: Theme.color(for: person)) {
                    selection = person.id
                }
                if isOutsider {
                    Image(systemName: "arrow.turn.down.right")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textFaint)
                        .help("Works elsewhere")
                }
                Spacer(minLength: 0)
            }
            if let role = role?.nilIfBlank {
                Text(role)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.leading, Theme.Spacing.small)
            }
        }
    }

    // MARK: Data

    private var projects: [Project] {
        store.projects(inOrganization: organization.id)
    }

    private var employees: [Person] {
        store.members(ofOrganization: organization.id)
    }

    /// Employees not on any of this organization's projects.
    private var unassigned: [Person] {
        let staffed = Set(projects.flatMap { store.members(ofProject: $0.id).map(\.id) })
        return employees.filter { !staffed.contains($0.id) }
    }

    private var subtitle: String {
        let projectCount = projects.count
        let peopleCount = employees.count
        return
            "\(projectCount) project\(projectCount == 1 ? "" : "s") · \(peopleCount) \(peopleCount == 1 ? "person" : "people")"
    }
}
