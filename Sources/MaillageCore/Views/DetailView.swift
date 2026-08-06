import SwiftUI

/// Right pane: everything known about the selected entity.
public struct DetailView: View {
    @Environment(VaultStore.self) private var store
    @Binding var selection: EntityID?
    @Binding var editorRequest: EditorRequest?

    public init(selection: Binding<EntityID?>, editorRequest: Binding<EditorRequest?>) {
        self._selection = selection
        self._editorRequest = editorRequest
    }

    public var body: some View {
        Group {
            switch selection.flatMap({ store.entity(id: $0) }) {
            case .person(let person):
                detail(for: .person(person)) { PersonDetailBody(person: person, selection: $selection, editorRequest: $editorRequest) }
            case .organization(let org):
                detail(for: .organization(org)) { OrganizationDetailBody(organization: org, selection: $selection) }
            case .project(let project):
                detail(for: .project(project)) { ProjectDetailBody(project: project, selection: $selection) }
            case nil:
                EmptyStateView(
                    icon: "person.crop.circle",
                    title: "Nothing selected",
                    message: "Pick someone from the sidebar or click a node in the graph."
                )
            }
        }
        .background(Theme.bgPrimary)
    }

    @ViewBuilder
    private func detail<Body: View>(
        for entity: AnyEntity, @ViewBuilder body: () -> Body
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                EntityHeader(entity: entity, editorRequest: $editorRequest)
                body()

                if !entity.body.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                        SectionHeader("Notes")
                        Text(entity.body)
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.textNormal)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(Theme.Spacing.large)
        }
    }
}

// MARK: - Header

private struct EntityHeader: View {
    let entity: AnyEntity
    @Binding var editorRequest: EditorRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack(spacing: Theme.Spacing.small) {
                Circle()
                    .fill(Theme.color(for: entity))
                    .frame(width: 10, height: 10)

                Text(entity.displayName)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.textNormal)
                    .italic(isPlaceholder)

                Spacer()

                if isPlaceholder {
                    SecondaryButton("Add name…", icon: "person.badge.plus") {
                        editorRequest = .resolvePlaceholder(entity.id)
                    }
                }
                IconButton("pencil", help: "Edit \(entity.displayName)") {
                    editorRequest = .edit(entity.id)
                }
            }

            HStack(spacing: Theme.Spacing.small) {
                Text(entity.kind.rawValue.capitalized)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textFaint)
                Text(entity.id)
                    .font(Theme.Font.mono)
                    .foregroundStyle(Theme.textFaint)
                    .textSelection(.enabled)
            }

            if isPlaceholder {
                Text("Name unknown — this profile is a placeholder.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.placeholderColor)
            }
        }
    }

    private var isPlaceholder: Bool {
        entity.asPerson?.placeholder == true
    }
}

// MARK: - Person

private struct PersonDetailBody: View {
    @Environment(VaultStore.self) private var store
    let person: Person
    @Binding var selection: EntityID?
    @Binding var editorRequest: EditorRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            if person.email != nil || person.created != nil {
                Card {
                    if let email = person.email {
                        MetadataRow("Email", value: email, isMonospaced: true)
                    }
                    if let created = person.created {
                        MetadataRow("Added", value: created.description)
                    }
                }
            }

            membershipSection

            // Outgoing: stored on this person's own file.
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                HStack {
                    SectionHeader("Relations")
                    Spacer()
                    Button {
                        editorRequest = .addRelation(person.id)
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Add a relation from \(person.displayName)")
                }

                if person.relations.isEmpty {
                    Text("No relations yet.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textFaint)
                } else {
                    ForEach(person.relations) { relation in
                        HStack(spacing: Theme.Spacing.small) {
                            Text(relation.label)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.textMuted)
                                .frame(width: 110, alignment: .trailing)

                            Image(systemName: "arrow.right")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textFaint)

                            Pill(
                                store.displayName(for: relation.to.id) ?? relation.to.id,
                                color: targetColor(relation.to.id),
                                icon: store.entity(id: relation.to.id) == nil
                                    ? "exclamationmark.triangle" : nil
                            ) {
                                selection = relation.to.id
                            }

                            Spacer()

                            Button {
                                store.removeRelation(from: person.id, relation: relation)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.textFaint)
                            }
                            .buttonStyle(.plain)
                            .help("Remove this relation")
                        }
                    }
                }
            }

            BacklinksSection(entityID: person.id, selection: $selection)
        }
    }

    private func targetColor(_ id: EntityID) -> Color {
        guard let entity = store.entity(id: id) else { return Theme.projectColor }
        return Theme.color(for: entity)
    }

    @ViewBuilder
    private var membershipSection: some View {
        if !person.organizations.isEmpty || !person.projects.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                if !person.organizations.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                        SectionHeader("Organizations")
                        WrappingPills(
                            links: person.organizations,
                            color: Theme.organizationColor,
                            selection: $selection)
                    }
                }
                if !person.projects.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                        SectionHeader("Projects")
                        WrappingPills(
                            links: person.projects,
                            color: Theme.projectColor,
                            selection: $selection)
                    }
                }
            }
        }
    }
}

// MARK: - Backlinks

/// Relations pointing *at* this entity.
///
/// Derived in memory from other people's files — nothing here is stored on the
/// selected entity, which is what keeps relations one-way on disk.
private struct BacklinksSection: View {
    @Environment(VaultStore.self) private var store
    let entityID: EntityID
    @Binding var selection: EntityID?

    var body: some View {
        let backlinks = store.backlinks(for: entityID)

        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            SectionHeader("Referenced by", trailing: backlinks.isEmpty ? nil : "\(backlinks.count)")

            if backlinks.isEmpty {
                Text("Nobody links here yet.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textFaint)
            } else {
                ForEach(backlinks) { backlink in
                    HStack(spacing: Theme.Spacing.small) {
                        Pill(
                            store.displayName(for: backlink.from) ?? backlink.from,
                            color: Theme.personColor
                        ) {
                            selection = backlink.from
                        }

                        Image(systemName: "arrow.right")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textFaint)

                        Text(backlink.label)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.textMuted)

                        Spacer()
                    }
                }
            }
        }
    }
}

// MARK: - Organization

private struct OrganizationDetailBody: View {
    @Environment(VaultStore.self) private var store
    let organization: Organization
    @Binding var selection: EntityID?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            if organization.domain != nil || organization.created != nil {
                Card {
                    if let domain = organization.domain {
                        MetadataRow("Domain", value: domain, isMonospaced: true)
                    }
                    if let created = organization.created {
                        MetadataRow("Added", value: created.description)
                    }
                }
            }

            let members = store.members(ofOrganization: organization.id)
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                SectionHeader("People", trailing: members.isEmpty ? nil : "\(members.count)")
                if members.isEmpty {
                    Text("Nobody is linked to this organization yet.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textFaint)
                } else {
                    PillCloud(
                        items: members.map { ($0.id, $0.displayName, Theme.color(for: $0)) },
                        selection: $selection)
                }
            }

            let projects = store.projects(inOrganization: organization.id)
            if !projects.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    SectionHeader("Projects", trailing: "\(projects.count)")
                    PillCloud(
                        items: projects.map { ($0.id, $0.displayName, Theme.projectColor) },
                        selection: $selection)
                }
            }
        }
    }
}

// MARK: - Project

private struct ProjectDetailBody: View {
    @Environment(VaultStore.self) private var store
    let project: Project
    @Binding var selection: EntityID?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            Card {
                MetadataRow("Status", value: project.status.displayName)
                if let created = project.created {
                    MetadataRow("Added", value: created.description)
                }
            }

            if !project.organizations.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    SectionHeader("Organizations")
                    WrappingPills(
                        links: project.organizations,
                        color: Theme.organizationColor,
                        selection: $selection)
                }
            }

            let members = store.members(ofProject: project.id)
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                SectionHeader("People", trailing: members.isEmpty ? nil : "\(members.count)")
                if members.isEmpty {
                    Text("Nobody is linked to this project yet.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textFaint)
                } else {
                    PillCloud(
                        items: members.map { ($0.id, $0.displayName, Theme.color(for: $0)) },
                        selection: $selection)
                }
            }
        }
    }
}

// MARK: - Pill helpers

private struct WrappingPills: View {
    @Environment(VaultStore.self) private var store
    let links: [Wikilink]
    let color: Color
    @Binding var selection: EntityID?

    var body: some View {
        PillCloud(
            items: links.map { link in
                (link.id, store.displayName(for: link.id) ?? link.id, color)
            },
            selection: $selection)
    }
}

/// Flow layout of entity pills that wraps to the available width.
private struct PillCloud: View {
    let items: [(id: EntityID, title: String, color: Color)]
    @Binding var selection: EntityID?

    var body: some View {
        FlowLayout(spacing: Theme.Spacing.small) {
            ForEach(items, id: \.id) { item in
                Pill(item.title, color: item.color) {
                    selection = item.id
                }
            }
        }
    }
}

/// Minimal flow layout — SwiftUI has no built-in wrapping HStack.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
