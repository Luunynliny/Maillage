import SwiftUI

/// The middle pane, which answers the question implied by what's selected.
///
/// Four representations rather than one graph with filters, because each selection is a
/// different question and none of the four answers fits another's shape:
///
/// - **Nothing** — ``OrganizationBubblesView``, one circle per employer sized by headcount.
///   "What does my network look like?" is a question about companies, and drawing every person
///   here made a hairball you couldn't read a headcount off.
/// - **An organization** — ``OrganizationBoardView``, a card per project listing who staffs it.
///   What a company is working on and with whom is a roster question, and a roster is what
///   answers it: names in a column read at a glance, where dots on a rim have to be traced.
/// - **A person** — ``EgoGraphView``, them at the centre with their direct relations as
///   labelled spokes. One hop, because the labels are the payload and the second ring is
///   somebody else's network.
/// - **A project** — ``ProjectRosterView``, its participants and their roles. A role wants a
///   column, not an edge label at 11pt.
///
/// None of the four is simulated — the two graphs lay out from computed geometry and the two
/// boards from a stack — so each looks the same every time you open it. "Acme is the big one"
/// stays true between launches.
///
/// The mode follows the selection with no switch of its own: the sidebar section you
/// clicked already says which of the four you meant.
struct CenterPane: View {
    @Environment(VaultStore.self) private var store
    @Binding var selection: EntityID?
    /// Passed down so an empty view can offer the editor that fills it.
    @Binding var editorRequest: EditorRequest?
    /// Whether each subject view's header has its details folded out. Owned by ``RootView``
    /// so the choice outlives the selection it was made on.
    @Binding var isDetailVisible: Bool

    var body: some View {
        ZStack {
            Theme.bgPrimary.ignoresSafeArea()

            switch selection.flatMap({ store.entity(id: $0) }) {
            case .organization(let organization):
                OrganizationBoardView(
                    organization: organization, selection: $selection,
                    editorRequest: $editorRequest, isDetailVisible: $isDetailVisible)
            case .project(let project):
                ProjectRosterView(
                    project: project, selection: $selection,
                    editorRequest: $editorRequest, isDetailVisible: $isDetailVisible)
            case .person(let person):
                EgoGraphView(
                    person: person, selection: $selection,
                    editorRequest: $editorRequest, isDetailVisible: $isDetailVisible)
            // Nothing selected: the bubbles are the only view that stands on its own without a
            // subject, and they're where you click through to the other three.
            case nil:
                OrganizationBubblesView(selection: $selection)
            }
        }
    }
}

/// Header above the three subject views: what you're looking at, and — folded away until
/// asked for — everything known about it.
///
/// This band is the only place the subject is named. It used to share that job with a detail
/// column on the right, which meant the same name drawn twice side by side while the graph,
/// the widest thing in the app, was permanently narrowed by a pane of metadata worth one
/// glance. So the metadata moved here, under the name it describes, behind a chevron.
///
/// Collapsed by default: the graph is what you came for, and the details are an answer to a
/// question you have to ask. The state lives in ``RootView`` so unfolding it once keeps it
/// unfolded as you click from person to person.
///
/// The bubbles have no header, since nothing is selected and every circle labels itself.
/// Takes the whole subject rather than a title and a colour, because everything except the
/// subtitle is derivable from it — the name, the kind's hue, the italic that marks a
/// placeholder, the buttons that edit it and the details that describe it. The three subject
/// views each have their own subtitle (a headcount, a status, a job title) and nothing else
/// to say here, so that stays the one parameter.
struct CenterPaneHeader: View {
    let entity: AnyEntity
    let subtitle: String
    @Binding var isDetailVisible: Bool
    @Binding var selection: EntityID?
    @Binding var editorRequest: EditorRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The name and chevron together are the hit target, matching the sidebar's
            // section headings — the same gesture folds a section there and details here.
            // The edit buttons sit outside it, so editing never folds.
            HStack(spacing: Theme.Spacing.small) {
                HStack(spacing: Theme.Spacing.small) {
                    DisclosureChevron(isExpanded: isDetailVisible)

                    Circle()
                        .fill(Theme.color(for: entity))
                        .frame(width: Theme.entityDot, height: Theme.entityDot)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(entity.displayName)
                            .font(Theme.Font.heading)
                            .foregroundStyle(Theme.textNormal)
                            // Placeholder people are named in italic, as in the sidebar.
                            .italic(isPlaceholder)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(subtitle)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.textMuted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: Theme.Spacing.small)
                }
                .contentShape(Rectangle())
                .onTapGesture { isDetailVisible.toggle() }
                .clickableCursor()
                .help(isDetailVisible ? "Hide details" : "Show details")

                // Kept in the always-visible row: editing is something you do to the
                // subject, not a detail of it.
                if isPlaceholder {
                    SecondaryButton("Add name…", icon: "person.badge.plus") {
                        editorRequest = .resolvePlaceholder(entity.id)
                    }
                }
                IconButton("pencil", help: "Edit \(entity.displayName)") {
                    editorRequest = .edit(entity.id)
                }
            }
            .padding(.horizontal, Theme.Spacing.large)
            .padding(.vertical, Theme.Spacing.medium)

            if isDetailVisible {
                // Capped, and scrolls past the cap: a person with thirty backlinks would
                // otherwise push the graph out of the window entirely.
                ScrollView {
                    EntityDetails(
                        entity: entity, selection: $selection, editorRequest: $editorRequest)
                        .padding(.horizontal, Theme.Spacing.large)
                        .padding(.bottom, Theme.Spacing.large)
                }
                .frame(maxHeight: Theme.Height.detailsMax)
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.border).frame(height: Theme.hairline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgSecondary)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: Theme.hairline)
        }
    }

    private var isPlaceholder: Bool {
        entity.asPerson?.placeholder == true
    }
}
