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
                        SectionHeader(entity.bodyTitle)
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
            if !metadata.isEmpty {
                MetadataList(metadata)
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
                    .clickableCursor()
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
                            .clickableCursor()
                            .help("Remove this relation")
                        }
                    }
                }
            }

            BacklinksSection(entityID: person.id, selection: $selection)
        }
    }

    private var metadata: [MetadataList.Item] {
        var items: [MetadataList.Item] = []
        if let role = person.role {
            items.append(.init("Role", value: role))
        }
        if let email = person.email {
            items.append(.init("Email", value: email, isMonospaced: true))
        }
        if let created = person.created {
            items.append(.init("Added", value: created.description))
        }
        return items
    }

    private func targetColor(_ id: EntityID) -> Color {
        guard let entity = store.entity(id: id) else { return Theme.projectColor }
        return Theme.color(for: entity)
    }

    @ViewBuilder
    private var membershipSection: some View {
        if person.organization != nil || !person.projects.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                if let employer = person.organization {
                    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                        SectionHeader("Organization")
                        WrappingPills(
                            links: [employer],
                            color: Theme.organizationColor,
                            selection: $selection)
                    }
                }
                if !person.projects.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                        SectionHeader("Projects")
                        // The role rides in the pill: what someone does on a project is
                        // the reason they're listed, so it shouldn't need a second click.
                        PillCloud(
                            items: person.projects.map { membership in
                                (
                                    membership.to.id,
                                    projectLabel(membership),
                                    Theme.projectColor
                                )
                            },
                            selection: $selection)
                    }
                }
            }
        }
    }

    /// `Maillage · Lead`, or just the project name when no role is recorded.
    private func projectLabel(_ membership: ProjectMembership) -> String {
        let name = store.displayName(for: membership.to.id) ?? membership.to.id
        guard let role = membership.role?.nilIfBlank else { return name }
        return "\(name) · \(role)"
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
            if !metadata.isEmpty {
                MetadataList(metadata)
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

    private var metadata: [MetadataList.Item] {
        var items: [MetadataList.Item] = []
        if let domain = organization.domain {
            items.append(.init("Domain", value: domain, isMonospaced: true))
        }
        if let created = organization.created {
            items.append(.init("Added", value: created.description))
        }
        return items
    }
}

// MARK: - Project

private struct ProjectDetailBody: View {
    @Environment(VaultStore.self) private var store
    let project: Project
    @Binding var selection: EntityID?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            MetadataList(metadata)

            if !project.organizations.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    SectionHeader("Organizations")
                    WrappingPills(
                        links: project.organizations,
                        color: Theme.organizationColor,
                        selection: $selection)
                }
            }

            let participants = store.participants(ofProject: project.id)
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                SectionHeader(
                    "People", trailing: participants.isEmpty ? nil : "\(participants.count)")
                if participants.isEmpty {
                    Text("Nobody is linked to this project yet — add people by editing it.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textFaint)
                } else {
                    // Display only: staffing happens in the editor, so the detail pane has
                    // no half-committed state to reconcile. The role rides in the pill.
                    PillCloud(
                        items: participants.map { participant in
                            (
                                participant.person.id,
                                participantLabel(participant),
                                Theme.color(for: participant.person)
                            )
                        },
                        selection: $selection)
                }
            }
        }
    }

    /// `Marie Dupont · Lead`, or just the name when no role is recorded.
    private func participantLabel(_ participant: (person: Person, role: String?)) -> String {
        guard let role = participant.role?.nilIfBlank else { return participant.person.displayName }
        return "\(participant.person.displayName) · \(role)"
    }

    /// Status is always present, so this list never collapses to nothing.
    private var metadata: [MetadataList.Item] {
        var items: [MetadataList.Item] = [
            .init("Status", value: project.status.displayName)
        ]
        if let created = project.created {
            items.append(.init("Added", value: created.description))
        }
        return items
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
///
/// Shared with the centre pane's organization board, so selecting an entity looks and
/// behaves identically wherever a set of links is shown.
struct PillCloud: View {
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
