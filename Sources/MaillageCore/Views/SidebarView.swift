import SwiftUI

/// Left pane: every entity grouped by kind, each section headed by a "+" that creates one.
///
/// No filter box: narrowing the vault is the ⌘K palette's job, and a search field here only
/// duplicated it while pushing the vault's contents down the pane. The create buttons sit on
/// the sections rather than in one menu, so the kind being made is implied by where you
/// clicked. Unnamed people are rare enough to stay on ⌘⇧N alone.
public struct SidebarView: View {
    @Environment(VaultStore.self) private var store
    @Binding var selection: EntityID?
    @Binding var editorRequest: EditorRequest?

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
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                SectionHeader(kind.displayName, trailing: rows.isEmpty ? nil : "\(rows.count)")
                AddButton(help: "New \(kind.rawValue)") {
                    editorRequest = .new(kind)
                }
            }
            .padding(.horizontal, Theme.Spacing.small)

            if rows.isEmpty {
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
