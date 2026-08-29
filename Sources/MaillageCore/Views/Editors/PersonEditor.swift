import SwiftUI

/// Creates or edits a person. Also handles resolving a placeholder, where the name
/// fields start empty and saving renames the underlying file.
struct PersonEditor: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// `nil` when creating.
    let existing: Person?
    /// Whether the sheet opens in placeholder mode. Only the starting position of the
    /// toggle: File ▸ New Unnamed Person opens with it on, the sidebar's "+" with it off, and
    /// either can be flipped without closing the sheet.
    let isPlaceholder: Bool
    /// True when filling in the name of an existing placeholder.
    let isResolving: Bool
    var onSaved: (EntityID) -> Void = { _ in }

    @State private var firstname = ""
    @State private var lastname = ""
    @State private var email = ""
    @State private var role = ""
    @State private var descriptor = ""
    @State private var notes = ""
    /// Holds at most one — see the `limit: 1` on its field.
    @State private var organizations: Set<EntityID> = []
    @State private var projects: Set<EntityID> = []
    /// Roles already recorded per project, kept aside so saving this sheet — which only
    /// edits *which* projects — never discards what the person does on them.
    @State private var projectRoles: [EntityID: String] = [:]
    /// Live placeholder state, seeded from ``isPlaceholder`` on appear.
    @State private var isBlank = false
    /// Staged, applied in ``save()`` — see ``LogoChange``.
    @State private var logo: LogoChange = .unchanged

    var body: some View {
        EditorSheet(
            title: title,
            subtitle: subtitle,
            confirmTitle: existing == nil ? "Create" : "Save",
            isConfirmEnabled: isValid,
            onConfirm: save,
            onCancel: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                // Only offered while creating. Flipping it on an existing person would mean
                // discarding a name, which is `renameEntity`'s job, not this sheet's.
                if existing == nil {
                    ToggleField(
                        "No name yet",
                        caption:
                            "For someone you've heard about but can't name — \"the head of AA\". You can fill the name in later.",
                        isOn: $isBlank)
                }

                if isBlank {
                    FormField(
                        "Description",
                        placeholder: "e.g. Head of AA",
                        text: $descriptor)
                } else {
                    HStack(spacing: Theme.Spacing.medium) {
                        FormField("First name", placeholder: "Marie", text: $firstname)
                        FormField("Last name", placeholder: "Dupont", text: $lastname)
                    }
                    FormField("Email", placeholder: "marie@example.com", text: $email)
                }

                // Offered even for a placeholder: you may have a face before you have a name,
                // and it's the same file either way — resolving carries it across.
                LogoField(kind: .person, existingID: existing?.id, change: $logo)

                // Offered in both modes: what someone does is often the first thing you
                // learn about them, and for a placeholder it's the one thing you know.
                FormField("Role", placeholder: "Head of Engineering", text: $role)

                // One employer at a time, so picking a second replaces the first.
                MultiSelectField(
                    label: "Organization",
                    options: store.allOrganizations.map { ($0.id, $0.displayName) },
                    selected: $organizations,
                    kind: .organization,
                    prompt: "Search organizations",
                    limit: 1)

                // Carries a role per project, the same pairing the project editor shows from
                // the other side — one membership, editable from either end.
                ProjectMembershipsField(
                    projects: store.allProjects,
                    selected: $projects,
                    roles: $projectRoles)

                NotesField(text: $notes)
            }
        }
        .onAppear(perform: populate)
    }

    private var title: String {
        if isResolving { return "Add a name" }
        if let existing { return "Edit \(existing.displayName)" }
        return "New person"
    }

    /// Only the resolving case needs one — the toggle carries its own explanation.
    private var subtitle: String? {
        isResolving
            ? "Filling in the name renames the file and updates every link pointing at this person."
            : nil
    }

    private var isValid: Bool {
        if isBlank { return descriptor.nilIfBlank != nil }
        return firstname.nilIfBlank != nil || lastname.nilIfBlank != nil
    }

    private func populate() {
        isBlank = isPlaceholder
        guard let existing else { return }
        firstname = existing.firstname ?? ""
        lastname = existing.lastname ?? ""
        email = existing.email ?? ""
        role = existing.role ?? ""
        descriptor = existing.descriptor ?? ""
        notes = existing.body
        organizations = Set(existing.organization.map { [$0.id] } ?? [])
        projects = Set(existing.projects.map(\.to.id))
        projectRoles = existing.projects.reduce(into: [:]) { roles, membership in
            if let role = membership.role { roles[membership.to.id] = role }
        }
    }

    private func save() {
        let orgLink = organizations.min().map(Wikilink.init)
        // `nilIfBlank`, so a role cleared in the field is dropped rather than written as "".
        let memberships = projects.sorted().map {
            ProjectMembership(to: $0, role: projectRoles[$0]?.nilIfBlank)
        }

        if var person = existing {
            if isResolving {
                person.role = role.nilIfBlank
                person.organization = orgLink
                person.projects = memberships
                person.body = notes
                _ = store.update(person)

                // Applied to whichever id the person ends up under: resolving renames the file,
                // and `VaultWriter.rename` moves any logo with it — so writing to the old slug
                // first and letting the rename carry it would work too, but staging it here
                // keeps one code path for all three outcomes.
                let resolved = store.resolvePlaceholder(
                    person.id,
                    firstname: firstname,
                    lastname: lastname,
                    email: email)
                store.apply(logo, kind: .person, id: resolved?.id ?? person.id)
                if let resolved { onSaved(resolved.id) }
            } else {
                person.firstname = firstname.nilIfBlank
                person.lastname = lastname.nilIfBlank
                person.email = email.nilIfBlank
                person.role = role.nilIfBlank
                person.descriptor = descriptor.nilIfBlank
                person.organization = orgLink
                person.projects = memberships
                person.body = notes
                if store.update(person) {
                    store.apply(logo, kind: .person, id: person.id)
                    onSaved(person.id)
                }
            }
        } else if let created = store.createPerson(
            // Only the fields the current mode shows: text typed before the toggle was
            // flipped is still in state, and a placeholder with a name is a contradiction.
            firstname: isBlank ? nil : firstname,
            lastname: isBlank ? nil : lastname,
            email: isBlank ? nil : email,
            role: role,
            descriptor: isBlank ? descriptor : nil,
            placeholder: isBlank,
            organization: orgLink,
            projects: memberships,
            body: notes)
        {
            // Only now is there an id to name the file after.
            store.apply(logo, kind: .person, id: created.id)
            onSaved(created.id)
        }
        dismiss()
    }
}
