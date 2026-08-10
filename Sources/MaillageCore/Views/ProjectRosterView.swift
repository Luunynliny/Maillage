import SwiftUI

/// Everyone on a project and what they do there.
///
/// A table rather than a graph: the payload is one role string per participant, and a role
/// read down an aligned column is legible in a way an 11pt label on a moving edge is not.
/// Display-only — the roster is staffed in the project's editor, so a partly filled roster
/// never reaches the vault.
struct ProjectRosterView: View {
    @Environment(VaultStore.self) private var store

    let project: Project
    @Binding var selection: EntityID?
    /// So the empty state and the header can open the editor, where staffing happens.
    @Binding var editorRequest: EditorRequest?
    /// Whether the header's details section is folded out. Owned by ``RootView``.
    @Binding var isDetailVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            CenterPaneHeader(
                entity: .project(project),
                subtitle: subtitle,
                isDetailVisible: $isDetailVisible,
                selection: $selection,
                editorRequest: $editorRequest)

            if participants.isEmpty {
                EmptyStateView(
                    icon: "person.2",
                    title: "No participants yet",
                    message:
                        "Edit \(project.displayName) to add people and say what each of them does on it.",
                    actionTitle: "Add people…",
                    action: { editorRequest = .edit(project.id) }
                )
            } else {
                roster
            }
        }
    }

    private var roster: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                columnHeadings

                ForEach(participants, id: \.person.id) { participant in
                    row(participant.person, role: participant.role)
                }
            }
            .padding(Theme.Spacing.large)
        }
    }

    private var columnHeadings: some View {
        HStack(spacing: Theme.Spacing.medium) {
            SectionHeader("Participant")
                .frame(maxWidth: .infinity, alignment: .leading)
            SectionHeader("Role")
                .frame(width: Theme.Width.rosterRole, alignment: .leading)
            SectionHeader("Organization")
                .frame(width: Theme.Width.rosterEmployer, alignment: .leading)
        }
        .padding(.bottom, Theme.Spacing.small)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: Theme.hairline)
        }
    }

    private func row(_ person: Person, role: String?) -> some View {
        HStack(spacing: Theme.Spacing.medium) {
            HStack(spacing: 0) {
                EntityLink(
                    title: person.displayName,
                    kind: .person,
                    id: person.id,
                    size: Theme.Avatar.tableRow,
                    isPlaceholder: person.placeholder
                ) {
                    selection = person.id
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Dimmed rather than blank, so an unrecorded role reads as a gap to fill.
            Text(role?.nilIfBlank ?? "—")
                .font(Theme.Font.body)
                .foregroundStyle(role?.nilIfBlank == nil ? Theme.textFaint : Theme.textNormal)
                .frame(width: Theme.Width.rosterRole, alignment: .leading)

            employerCell(person)
                .frame(width: Theme.Width.rosterEmployer, alignment: .leading)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    @ViewBuilder
    private func employerCell(_ person: Person) -> some View {
        if let employer = person.organization,
            let name = store.displayName(for: employer.id)
        {
            // Its logo too, not only the participant's: in a column of employers the logo is
            // the fastest way to see that three of them work for the same one, which is what
            // the column is there to tell you. Blue text alone said "organization", which the
            // heading already says.
            //
            // At the participant's size, for the same reason — this is the column that gets
            // compared down its length, and two columns of logos have to be weighted alike or
            // the smaller one reads as subordinate detail rather than as the other half of the
            // row.
            EntityLink(
                title: name, kind: .organization, id: employer.id,
                size: Theme.Avatar.tableRow
            ) {
                selection = employer.id
            }
        } else {
            Text("—")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textFaint)
        }
    }

    // MARK: Data

    private var participants: [(person: Person, role: String?)] {
        store.participants(ofProject: project.id)
    }

    private var subtitle: String {
        let count = participants.count
        let named = participants.filter { $0.role?.nilIfBlank != nil }.count
        let people = "\(count) \(count == 1 ? "participant" : "participants")"
        // Only worth mentioning while some roles are still blank.
        return named == count ? people : "\(people) · \(count - named) without a role"
    }
}
