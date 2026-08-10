import SwiftUI

/// Left pane: every entity grouped by kind, each section headed by a "+" that creates one and
/// a chevron that folds it away.
///
/// No filter box: narrowing the vault is the ⌘K palette's job, and a search field here only
/// duplicated it while pushing the vault's contents down the pane. The create buttons sit on
/// the sections rather than in one menu, so the kind being made is implied by where you
/// clicked. Unnamed people are rare enough to stay on ⌘⇧N alone.
public struct SidebarView: View {
    @Environment(VaultStore.self) private var store
    @Binding var selection: EntityID?
    @Binding var editorRequest: EditorRequest?

    /// Which sections are folded shut. A set of the collapsed kinds rather than a flag per
    /// kind, so "expanded" stays the default for any kind added later — and so the whole
    /// state is one value to persist if that's ever wanted.
    @State private var collapsed: Set<EntityKind> = []

    public init(selection: Binding<EntityID?>, editorRequest: Binding<EditorRequest?>) {
        self._selection = selection
        self._editorRequest = editorRequest
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.large) {
                    section(
                        kind: .person,
                        rows: store.allPeople.map {
                            Row(
                                id: $0.id, title: $0.displayName,
                                isPlaceholder: $0.placeholder)
                        })

                    section(
                        kind: .organization,
                        rows: store.allOrganizations.map {
                            Row(id: $0.id, title: $0.displayName, isPlaceholder: false)
                        })

                    section(
                        kind: .project,
                        rows: store.allProjects.map {
                            Row(id: $0.id, title: $0.displayName, isPlaceholder: false)
                        })
                }
                .padding(.horizontal, Theme.Spacing.small)
                .padding(.vertical, Theme.Spacing.medium)
            }

            if !store.snapshot.issues.isEmpty {
                issuesFooter
            }
        }
        .background(Theme.bgSecondary)
    }

    // MARK: Header

    /// The app's name, and the way back out of whatever you've selected.
    ///
    /// Clicking it clears the selection, which is what puts the organization bubbles back in
    /// the centre pane — the overview of the whole vault. Every other route into that view is
    /// an absence of a click, so without this there was no *action* that reached it: once you
    /// had selected anything you were stuck one entity or another for the rest of the session.
    /// A title in the top-left going home is the convention every app on the machine follows.
    ///
    /// The whole band is the target, not just the six letters, and it stays clickable while
    /// nothing is selected — going where you already are is harmless, and a hit target that
    /// disappears depending on state is worse than a no-op.
    private var header: some View {
        HStack {
            Text("maillage")
                .font(Theme.Font.heading)
                .foregroundStyle(Theme.textNormal)
            Spacer()
        }
        .padding(Theme.Spacing.medium)
        .contentShape(Rectangle())
        .onTapGesture { selection = nil }
        .clickableCursor()
        .help("Show every organization")
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: Theme.hairline)
        }
    }

    // MARK: Sections

    /// No colour: the row's avatar derives its own from the kind of the section it's in, and
    /// from whether the entity has a logo — which only the store knows.
    private struct Row: Identifiable {
        let id: EntityID
        let title: String
        let isPlaceholder: Bool
    }

    @ViewBuilder
    private func section(kind: EntityKind, rows: [Row]) -> some View {
        let isCollapsed = collapsed.contains(kind)

        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                // The whole title is the hit target, not just the chevron: a 10pt glyph is a
                // mean thing to ask someone to hit, and the header has no other click job.
                // The "+" is a separate button outside it, so creating never folds.
                //
                // `contentShape` plus `onTapGesture` rather than a `Button`, the same idiom
                // `RoleField` uses for its box: a plain `Button` here took first responder on
                // launch and wore a blue focus ring, which read as a selected row in a pane
                // where selection means something else entirely.
                HStack(spacing: Theme.Spacing.xs) {
                    DisclosureChevron(isExpanded: !isCollapsed)
                    SectionHeader(
                        kind.displayName,
                        trailing: rows.isEmpty ? nil : "\(rows.count)")
                    // Claims the rest of the row so the whole width folds the section, not
                    // just the words — the count travels with the title rather than being
                    // pushed out to meet the "+".
                    Spacer(minLength: Theme.Spacing.xs)
                }
                .contentShape(Rectangle())
                .onTapGesture { toggle(kind) }
                .clickableCursor()
                .help(isCollapsed ? "Show \(kind.displayName)" : "Hide \(kind.displayName)")

                AddButton(help: "New \(kind.rawValue)") {
                    editorRequest = .new(kind)
                }
            }
            .padding(.horizontal, Theme.Spacing.small)

            if isCollapsed {
                // Nothing: the count in the header already says what's folded away, so a
                // collapsed section costs exactly one row of height.
                EmptyView()
            } else if rows.isEmpty {
                Text("None yet")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textFaint)
                    .padding(.horizontal, Theme.Spacing.small)
                    .padding(.vertical, 2)
            } else {
                ForEach(rows) { row in
                    SidebarRow(
                        title: row.title,
                        kind: kind,
                        id: row.id,
                        isSelected: selection == row.id,
                        isPlaceholder: row.isPlaceholder
                    ) {
                        selection = row.id
                    }
                    .contextMenu {
                        Button("Edit…") { editorRequest = .edit(row.id) }
                        Button("Delete", role: .destructive) {
                            editorRequest = .confirmDelete(row.id)
                        }
                    }
                }
            }
        }
    }

    /// Unanimated on purpose: folding a section is navigation, not an effect, and the rows
    /// should be gone by the time the click finishes rather than sliding for a fifth of a
    /// second first.
    private func toggle(_ kind: EntityKind) {
        if collapsed.contains(kind) {
            collapsed.remove(kind)
        } else {
            collapsed.insert(kind)
        }
    }

    private var issuesFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(
                "\(store.snapshot.issues.count) file\(store.snapshot.issues.count == 1 ? "" : "s") couldn't be read",
                systemImage: "exclamationmark.triangle"
            )
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.projectColor)

            ForEach(store.snapshot.issues.prefix(3)) { issue in
                Text(issue.path)
                    .font(Theme.Font.mono)
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
                    .help(issue.message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.small)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.border).frame(height: Theme.hairline)
        }
    }
}
