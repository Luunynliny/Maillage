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
                                color: Theme.color(for: $0),
                                isPlaceholder: $0.placeholder)
                        })

                    section(
                        kind: .organization,
                        rows: store.allOrganizations.map {
                            Row(
                                id: $0.id, title: $0.displayName,
                                color: Theme.organizationColor,
                                isPlaceholder: false)
                        })

                    section(
                        kind: .project,
                        rows: store.allProjects.map {
                            Row(
                                id: $0.id, title: $0.displayName,
                                color: Theme.projectColor,
                                isPlaceholder: false)
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

    private var header: some View {
        HStack {
            Text("maillage")
                .font(Theme.Font.heading)
                .foregroundStyle(Theme.textNormal)
            Spacer()
        }
        .padding(Theme.Spacing.medium)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: Theme.hairline)
        }
    }

    // MARK: Sections

    private struct Row: Identifiable {
        let id: EntityID
        let title: String
        let color: Color
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
                        dotColor: row.color,
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

    /// Animated so the rows slide rather than blink, which is what makes it read as folding
    /// rather than as the list being replaced.
    private func toggle(_ kind: EntityKind) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if collapsed.contains(kind) {
                collapsed.remove(kind)
            } else {
                collapsed.insert(kind)
            }
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
