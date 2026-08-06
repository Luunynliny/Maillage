import SwiftUI

/// Left pane: every entity grouped by kind, with a filter box and create menu.
public struct SidebarView: View {
    @Environment(VaultStore.self) private var store
    @Binding var selection: EntityID?
    @Binding var editorRequest: EditorRequest?

    @State private var filter = ""

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
                        rows: filteredPeople.map {
                            Row(
                                id: $0.id, title: $0.displayName,
                                color: Theme.color(for: $0),
                                isPlaceholder: $0.placeholder)
                        })

                    section(
                        kind: .organization,
                        rows: filteredOrganizations.map {
                            Row(
                                id: $0.id, title: $0.displayName,
                                color: Theme.organizationColor,
                                isPlaceholder: false)
                        })

                    section(
                        kind: .project,
                        rows: filteredProjects.map {
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
        VStack(spacing: Theme.Spacing.small) {
            HStack {
                Text("maillage")
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.textNormal)
                Spacer()
                createMenu
            }

            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textFaint)
                TextField("Filter", text: $filter)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textNormal)
                if !filter.isEmpty {
                    Button {
                        filter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.textFaint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.small)
            .padding(.vertical, 5)
            .background(Theme.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium)
                    .stroke(Theme.border, lineWidth: Theme.hairline)
            )
        }
        .padding(Theme.Spacing.medium)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: Theme.hairline)
        }
    }

    private var createMenu: some View {
        Menu {
            Button("New Person…") { editorRequest = .newPerson }
            Button("New Unnamed Person…") { editorRequest = .newPlaceholder }
            Divider()
            Button("New Organization…") { editorRequest = .newOrganization }
            Button("New Project…") { editorRequest = .newProject }
        } label: {
            Image(systemName: "plus")
                .font(Theme.Font.body.weight(.semibold))
                .foregroundStyle(Theme.textMuted)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Create a new entry")
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
            SectionHeader(kind.displayName, trailing: rows.isEmpty ? nil : "\(rows.count)")
                .padding(.horizontal, Theme.Spacing.small)

            if rows.isEmpty {
                Text(filter.isEmpty ? "None yet" : "No matches")
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

    // MARK: Filtering

    private func matches(_ text: String) -> Bool {
        filter.isEmpty || text.localizedCaseInsensitiveContains(filter)
    }

    private var filteredPeople: [Person] {
        store.allPeople.filter { matches($0.displayName) || matches($0.email ?? "") }
    }

    private var filteredOrganizations: [Organization] {
        store.allOrganizations.filter { matches($0.displayName) }
    }

    private var filteredProjects: [Project] {
        store.allProjects.filter { matches($0.displayName) }
    }
}
