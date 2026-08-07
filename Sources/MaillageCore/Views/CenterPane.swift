import SwiftUI

/// The middle pane, which answers the question implied by what's selected.
///
/// Three representations rather than one graph with filters, because the three questions
/// have different shapes:
///
/// - **A person** — everyone, clustered by employer. The only view where person↔person
///   relations make the topology irregular, which is the one thing a force layout is for.
/// - **An organization** — its projects and who staffs each. A two-level containment
///   hierarchy, so it's laid out deterministically instead of simulated.
/// - **A project** — its participants and their roles. A role wants a column, not an
///   edge label at 11pt in a moving layout.
///
/// The mode follows the selection with no switch of its own: the sidebar section you
/// clicked already says which of the three you meant.
struct CenterPane: View {
    @Environment(VaultStore.self) private var store
    @Binding var selection: EntityID?
    /// Passed down so an empty view can offer the editor that fills it.
    @Binding var editorRequest: EditorRequest?

    var body: some View {
        ZStack {
            Theme.bgPrimary.ignoresSafeArea()

            switch selection.flatMap({ store.entity(id: $0) }) {
            case .organization(let organization):
                OrganizationBoardView(organization: organization, selection: $selection)
            case .project(let project):
                ProjectRosterView(
                    project: project, selection: $selection, editorRequest: $editorRequest)
            // A person, or nothing selected yet: the network is the sensible default,
            // since it's the only view that stands on its own without a subject.
            case .person, nil:
                PeopleGraphView(selection: $selection)
            }
        }
    }
}

/// Header shown above the two laid-out views, naming the subject the rows belong to.
///
/// The detail pane names it too, but the centre pane is wide and scrollable — without this
/// a board of project cards has no anchor once you've scrolled.
struct CenterPaneHeader: View {
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.small) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.textNormal)
                Spacer(minLength: 0)
            }
            Text(subtitle)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, Theme.Spacing.large)
        .padding(.vertical, Theme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgSecondary)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: Theme.hairline)
        }
    }
}
