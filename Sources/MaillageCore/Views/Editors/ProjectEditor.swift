import SwiftUI

struct ProjectEditor: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let existing: Project?
    var onSaved: (EntityID) -> Void = { _ in }

    @State private var name = ""
    @State private var status: ProjectStatus = .active
    /// Holds at most one — see the `limit: 1` on its field.
    @State private var organizations: Set<EntityID> = []
    @State private var notes = ""
    /// The intended roster. Applied on save, so an abandoned sheet changes nobody's file.
    @State private var participants: Set<EntityID> = []
    @State private var roles: [EntityID: String] = [:]
    /// Staged, applied in ``save()`` — see ``LogoChange``.
    @State private var logo: LogoChange = .unchanged

    var body: some View {
        EditorSheet(
            title: existing == nil ? "New project" : "Edit \(existing!.displayName)",
            confirmTitle: existing == nil ? "Create" : "Save",
            isConfirmEnabled: name.nilIfBlank != nil,
            onConfirm: save,
            onCancel: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                FormField("Name", placeholder: "Maillage", text: $name)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Status")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textMuted)
                    Picker("", selection: $status) {
                        ForEach(ProjectStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                LogoField(kind: .project, existingID: existing?.id, change: $logo)

                // One owner at a time, so picking a second replaces the first.
                MultiSelectField(
                    label: "Organization",
                    options: store.allOrganizations.map { ($0.id, $0.displayName) },
                    selected: $organizations,
                    kind: .organization,
                    prompt: "Search organizations",
                    limit: 1)

                // Staffing the project is part of describing it, so it happens here rather
                // than one person at a time from their profiles. Written to the people's
                // files on save — the project file never lists its roster.
                ParticipantsField(
                    people: store.allPeople,
                    selected: $participants,
                    roles: $roles)

                NotesField(text: $notes, title: "Description")
            }
        }
        .onAppear(perform: populate)
    }

    private func populate() {
        guard let existing else { return }
        name = existing.name
        status = existing.status
        organizations = Set(existing.organization.map { [$0.id] } ?? [])
        notes = existing.body

        let roster = store.participants(ofProject: existing.id)
        participants = Set(roster.map(\.person.id))
        roles = roster.reduce(into: [:]) { roles, entry in
            if let role = entry.role { roles[entry.person.id] = role }
        }
    }

    private func save() {
        let orgLink = organizations.min().map(Wikilink.init)
        // Sorted so the writes are deterministic, which keeps them diffable in git.
        let roster = participants.sorted().map { (person: $0, role: roles[$0]?.nilIfBlank) }

        if var project = existing {
            project.name = name
            project.status = status
            project.organization = orgLink
            project.body = notes
            if store.update(project) {
                store.setParticipants(ofProject: project.id, to: roster)
                store.apply(logo, kind: .project, id: project.id)
                onSaved(project.id)
            }
        } else if let created = store.createProject(
            name: name, status: status, organization: orgLink, body: notes)
        {
            store.setParticipants(ofProject: created.id, to: roster)
            store.apply(logo, kind: .project, id: created.id)
            onSaved(created.id)
        }
        dismiss()
    }
}
