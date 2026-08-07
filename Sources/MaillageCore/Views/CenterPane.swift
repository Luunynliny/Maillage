import SwiftUI

/// The middle pane, which answers the question implied by what's selected.
///
/// Four representations rather than one graph with filters, because each selection is a
/// different question and none of the four answers fits another's shape:
///
/// - **Nothing** — ``OrganizationBubblesView``, one circle per employer sized by headcount.
///   "What does my network look like?" is a question about companies, and drawing every person
///   here made a hairball you couldn't read a headcount off.
/// - **An organization** — ``OrganizationRingView``, its people in arcs by project with their
///   relations bundled through the middle. Who's here, on what, and who talks to whom.
/// - **A person** — ``EgoGraphView``, them at the centre with their direct relations as
///   labelled spokes. One hop, because the labels are the payload and the second ring is
///   somebody else's network.
/// - **A project** — ``ProjectRosterView``, its participants and their roles. A role wants a
///   column, not an edge label at 11pt.
///
/// All four are laid out from computed geometry rather than simulated, so each looks the same
/// every time you open it — "Acme is the big one" stays true between launches.
///
/// The mode follows the selection with no switch of its own: the sidebar section you
/// clicked already says which of the four you meant.
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
                OrganizationRingView(organization: organization, selection: $selection)
            case .project(let project):
                ProjectRosterView(
                    project: project, selection: $selection, editorRequest: $editorRequest)
            case .person(let person):
                EgoGraphView(
                    person: person, selection: $selection, editorRequest: $editorRequest)
            // Nothing selected: the bubbles are the only view that stands on its own without a
            // subject, and they're where you click through to the other three.
            case nil:
                OrganizationBubblesView(selection: $selection)
            }
        }
    }
}

/// Header shown above the three subject views, naming what you're looking at.
///
/// The detail pane names it too, but the centre pane is wide — without this a ring of dots or
/// a scrolled roster has no anchor saying whose it is. The bubbles have no header, since
/// nothing is selected and every circle labels itself.
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
