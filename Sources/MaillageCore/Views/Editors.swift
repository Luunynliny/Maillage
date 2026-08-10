import SwiftUI

/// What the app should present as a sheet. Driven from the sidebar, detail pane and
/// menu commands so there is a single place that decides which editor is open.
public enum EditorRequest: Identifiable, Hashable {
    case newPerson
    case newPlaceholder
    case newOrganization
    case newProject
    case edit(EntityID)
    case addRelation(EntityID)
    case resolvePlaceholder(EntityID)
    case confirmDelete(EntityID)

    public var id: String {
        switch self {
        case .newPerson: "new-person"
        case .newPlaceholder: "new-placeholder"
        case .newOrganization: "new-organization"
        case .newProject: "new-project"
        case .edit(let id): "edit-\(id)"
        case .addRelation(let id): "relation-\(id)"
        case .resolvePlaceholder(let id): "resolve-\(id)"
        case .confirmDelete(let id): "delete-\(id)"
        }
    }

    /// The create request for a kind, so callers that already have an ``EntityKind`` —
    /// the sidebar's per-section buttons — need no switch of their own.
    public static func new(_ kind: EntityKind) -> EditorRequest {
        switch kind {
        case .person: .newPerson
        case .organization: .newOrganization
        case .project: .newProject
        }
    }
}

// MARK: - Sheet chrome

/// Shared sheet frame so every editor has identical padding, title and footer.
struct EditorSheet<Content: View>: View {
    let title: String
    let subtitle: String?
    let confirmTitle: String
    let isConfirmEnabled: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        confirmTitle: String = "Save",
        isConfirmEnabled: Bool = true,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.confirmTitle = confirmTitle
        self.isConfirmEnabled = isConfirmEnabled
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.textNormal)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content

            HStack {
                Spacer()
                SecondaryButton("Cancel", action: onCancel)
                PrimaryButton(confirmTitle, isEnabled: isConfirmEnabled, action: onConfirm)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 460)
        .background(Theme.bgSecondary)
    }
}

// MARK: - Person editor

/// Creates or edits a person. Also handles resolving a placeholder, where the name
/// fields start empty and saving renames the underlying file.
struct PersonEditor: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// `nil` when creating.
    let existing: Person?
    /// Whether the sheet opens in placeholder mode. Only the starting position of the
    /// toggle: ⌘⇧N opens with it on, the sidebar's "+" with it off, and either can be
    /// flipped without closing the sheet.
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

                // Offered in both modes: what someone does is often the first thing you
                // learn about them, and for a placeholder it's the one thing you know.
                FormField("Role", placeholder: "Head of Engineering", text: $role)

                // One employer at a time, so picking a second replaces the first.
                MultiSelectField(
                    label: "Organization",
                    options: store.allOrganizations.map { ($0.id, $0.displayName) },
                    selected: $organizations,
                    color: Theme.organizationColor,
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
        let orgLink = organizations.sorted().first.map(Wikilink.init)
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

                if let resolved = store.resolvePlaceholder(
                    person.id,
                    firstname: firstname,
                    lastname: lastname,
                    email: email)
                {
                    onSaved(resolved.id)
                }
            } else {
                person.firstname = firstname.nilIfBlank
                person.lastname = lastname.nilIfBlank
                person.email = email.nilIfBlank
                person.role = role.nilIfBlank
                person.descriptor = descriptor.nilIfBlank
                person.organization = orgLink
                person.projects = memberships
                person.body = notes
                if store.update(person) { onSaved(person.id) }
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
            onSaved(created.id)
        }
        dismiss()
    }
}

// MARK: - Organization editor

struct OrganizationEditor: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let existing: Organization?
    var onSaved: (EntityID) -> Void = { _ in }

    @State private var name = ""
    @State private var domain = ""
    @State private var notes = ""

    var body: some View {
        EditorSheet(
            title: existing == nil ? "New organization" : "Edit \(existing!.displayName)",
            confirmTitle: existing == nil ? "Create" : "Save",
            isConfirmEnabled: name.nilIfBlank != nil,
            onConfirm: save,
            onCancel: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                FormField("Name", placeholder: "Acme Corp", text: $name)
                FormField("Domain", placeholder: "acme.com", text: $domain)
                NotesField(text: $notes)
            }
        }
        .onAppear {
            guard let existing else { return }
            name = existing.name
            domain = existing.domain ?? ""
            notes = existing.body
        }
    }

    private func save() {
        if var org = existing {
            org.name = name
            org.domain = domain.nilIfBlank
            org.body = notes
            if store.update(org) { onSaved(org.id) }
        } else if let created = store.createOrganization(
            name: name, domain: domain, body: notes)
        {
            onSaved(created.id)
        }
        dismiss()
    }
}

// MARK: - Project editor

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

                // One owner at a time, so picking a second replaces the first.
                MultiSelectField(
                    label: "Organization",
                    options: store.allOrganizations.map { ($0.id, $0.displayName) },
                    selected: $organizations,
                    color: Theme.organizationColor,
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
        let orgLink = organizations.sorted().first.map(Wikilink.init)
        // Sorted so the writes are deterministic, which keeps them diffable in git.
        let roster = participants.sorted().map { (person: $0, role: roles[$0]?.nilIfBlank) }

        if var project = existing {
            project.name = name
            project.status = status
            project.organization = orgLink
            project.body = notes
            if store.update(project) {
                store.setParticipants(ofProject: project.id, to: roster)
                onSaved(project.id)
            }
        } else if let created = store.createProject(
            name: name, status: status, organization: orgLink, body: notes)
        {
            store.setParticipants(ofProject: created.id, to: roster)
            onSaved(created.id)
        }
        dismiss()
    }
}

// MARK: - Relation editor

/// Adds a one-way labeled relation. The target can be an existing person or a new
/// placeholder created inline — which is the "you should meet the head of AA" flow.
struct RelationEditor: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let sourceID: EntityID

    @State private var label = ""
    @State private var targetID: EntityID?
    @State private var isCreatingPlaceholder = false
    @State private var newPlaceholderDescriptor = ""
    @State private var search = ""

    var body: some View {
        EditorSheet(
            title: "Add a relation",
            subtitle: subtitle,
            confirmTitle: "Add",
            isConfirmEnabled: isValid,
            onConfirm: save,
            onCancel: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                LabelField(label: $label, known: store.usedRelationLabels)

                Divider().overlay(Theme.border)

                if isCreatingPlaceholder {
                    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                        FormField(
                            "New unnamed person",
                            placeholder: "e.g. Head of AA",
                            text: $newPlaceholderDescriptor)
                        Button("Choose an existing person instead") {
                            isCreatingPlaceholder = false
                            newPlaceholderDescriptor = ""
                        }
                        .buttonStyle(.plain)
                        .clickableCursor()
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.accent)
                    }
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                        Text("To")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.textMuted)

                        // A relation points at exactly one person, so this stays
                        // single-select — the search is the same one the pickers use.
                        SearchField("Search people", text: $search) {
                            targetID = candidates.first?.id ?? targetID
                        }

                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(candidates) { person in
                                    SidebarRow(
                                        title: person.displayName,
                                        dotColor: Theme.color(for: person),
                                        isSelected: targetID == person.id,
                                        isPlaceholder: person.placeholder
                                    ) {
                                        targetID = person.id
                                    }
                                }
                            }
                        }
                        .frame(height: 140)

                        Button("Or create an unnamed person…") {
                            isCreatingPlaceholder = true
                            targetID = nil
                        }
                        .buttonStyle(.plain)
                        .clickableCursor()
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
    }

    private var subtitle: String? {
        guard let name = store.displayName(for: sourceID) else { return nil }
        return "Stored on \(name)'s profile only — the other person will see it as a backlink."
    }

    private var candidates: [Person] {
        store.allPeople
            .filter { $0.id != sourceID }
            .filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) }
    }

    private var isValid: Bool {
        guard label.nilIfBlank != nil else { return false }
        return isCreatingPlaceholder
            ? newPlaceholderDescriptor.nilIfBlank != nil
            : targetID != nil
    }

    private func save() {
        let resolvedTarget: EntityID?
        if isCreatingPlaceholder {
            resolvedTarget = store.createPerson(
                descriptor: newPlaceholderDescriptor, placeholder: true)?.id
        } else {
            resolvedTarget = targetID
        }

        if let target = resolvedTarget, let trimmed = label.nilIfBlank {
            store.addRelation(from: sourceID, to: target, label: trimmed)
        }
        dismiss()
    }
}

// MARK: - Shared fields

/// Names a relation by typing a label, or tapping one already used in the vault.
///
/// There is no preset vocabulary: the labels offered are whatever the person has used
/// before, so this starts bare and grows as they name relationships. Deliberately a plain
/// text field rather than a search box with a dropdown — a magnifier and a list of hits
/// read as a picker, so a brand-new label that matched nothing looked like it couldn't be
/// entered at all. Typing is the primary action here; the pills are the shortcut.
struct LabelField: View {
    @Binding var label: String
    /// Labels already used in the vault, most-used first.
    let known: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            FormField("Label", placeholder: "e.g. manager of", text: $label)

            if !matches.isEmpty {
                Text(label.isEmpty ? "Used before" : "Matching")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textFaint)

                FlowLayout(spacing: Theme.Spacing.xs) {
                    ForEach(matches, id: \.self) { suggestion in
                        Pill(suggestion, color: Theme.accent) { label = suggestion }
                    }
                }
            }
        }
    }

    /// Known labels matching what's typed. Filtered rather than trimmed to an exact match
    /// so the row stays put while typing instead of collapsing under the cursor.
    private var matches: [String] {
        known.filter { label.isEmpty || $0.localizedCaseInsensitiveContains(label) }
    }
}

/// Picks entities, used for org and project membership.
///
/// Laying every option out as a pill stops scaling once a vault holds hundreds of
/// organizations, so this is search-first: what you've picked stays pinned as removable
/// pills, and the options list below only appears once you type or focus the field.
struct MultiSelectField: View {
    let label: String
    let options: [(id: EntityID, title: String)]
    @Binding var selected: Set<EntityID>
    let color: Color
    /// Shown under the search field when nothing is typed yet.
    var prompt: String = "Search to add"
    /// How many can be held at once, or `nil` for no ceiling.
    ///
    /// `1` makes this a single-select — picking replaces rather than adds, which is how a
    /// person's employer is chosen. Deliberately not a separate component: the search,
    /// pills and option list are identical, only the arity differs.
    var limit: Int?

    @State private var search = ""
    @State private var isSearchFocused = false

    var body: some View {
        if !options.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(label)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textMuted)

                if !selectedOptions.isEmpty {
                    FlowLayout(spacing: Theme.Spacing.xs) {
                        ForEach(selectedOptions, id: \.id) { option in
                            Pill(option.title, color: color, icon: "xmark") {
                                selected.remove(option.id)
                            }
                        }
                    }
                }

                SearchField(
                    prompt,
                    text: $search,
                    isFocused: $isSearchFocused,
                    onSubmit: addFirstMatch)

                // Kept out of the way until asked for: an always-open list would push the
                // rest of the form down and make short vaults feel heavier than they are.
                if isSearchFocused || !search.isEmpty {
                    optionList
                }
            }
        }
    }

    private var optionList: some View {
        ScrollView {
            VStack(spacing: 1) {
                if matches.isEmpty {
                    Text("No matches")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.Spacing.small)
                        .padding(.vertical, 5)
                } else {
                    ForEach(matches, id: \.id) { option in
                        SidebarRow(
                            title: option.title,
                            dotColor: color,
                            isSelected: false
                        ) {
                            pick(option.id)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.xs)
        }
        .frame(maxHeight: 108)
        .background(Theme.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium)
                .stroke(Theme.border, lineWidth: Theme.hairline)
        )
    }

    /// Selected first, in the order the caller gave, so the pills don't reshuffle.
    private var selectedOptions: [(id: EntityID, title: String)] {
        options.filter { selected.contains($0.id) }
    }

    /// Anything not already picked that matches what's typed.
    private var matches: [(id: EntityID, title: String)] {
        options.filter {
            !selected.contains($0.id)
                && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))
        }
    }

    /// Return adds the top match, so a whole list can be built without the mouse.
    private func addFirstMatch() {
        guard let first = matches.first else { return }
        pick(first.id)
    }

    /// Adds `id`, making room by dropping earlier picks once ``limit`` is reached.
    ///
    /// Making room rather than refusing: at a limit of 1, clicking a second organization
    /// obviously means "this one instead", and a field that went inert until the first
    /// pill was dismissed would read as a bug.
    private func pick(_ id: EntityID) {
        if let limit, selected.count >= limit {
            let keep = selectedOptions.suffix(max(0, limit - 1)).map(\.id)
            selected = Set(keep)
        }
        selected.insert(id)
        search = ""
    }
}

/// Picks entities and gives each a role, for the two ends of project membership.
///
/// Search-first like ``MultiSelectField``, but a pick becomes a row rather than a pill,
/// because it carries a second field. Roles are held as a plain `[EntityID: String]` the
/// caller owns, so nothing is written until the sheet is saved — a half-filled roster in an
/// unsaved editor must not reach the vault.
struct RoleAssignmentField: View {
    /// Everything pickable, in display order.
    let options: [(id: EntityID, title: String, color: Color, isPlaceholder: Bool)]
    let label: String
    let prompt: String
    /// Shown in place of the control when there is nothing to pick.
    let emptyMessage: String
    @Binding var selected: Set<EntityID>
    /// Role per entity. Entries for unselected ids are kept, so removing something and
    /// adding it back keeps the role it had.
    @Binding var roles: [EntityID: String]

    @State private var search = ""
    @State private var isSearchFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            // The role column gets its own header, since an empty input beside a name says
            // nothing about what goes in it. Only once there are rows to head, and pinned to
            // the same width as the field below so the two stay aligned.
            HStack(spacing: Theme.Spacing.small) {
                Text(label)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textMuted)

                if !selectedOptions.isEmpty {
                    Spacer(minLength: 0)
                    Text("Role")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: Theme.Width.roleField, alignment: .leading)
                        // Matches the field's own horizontal padding, so the header sits
                        // over the text it labels rather than over the box's edge.
                        .padding(.horizontal, Theme.Spacing.small)
                }
            }

            if options.isEmpty {
                Text(emptyMessage)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textFaint)
            } else {
                if !selectedOptions.isEmpty {
                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(selectedOptions, id: \.id) { option in
                            row(option)
                        }
                    }
                }

                SearchField(
                    prompt,
                    text: $search,
                    isFocused: $isSearchFocused,
                    onSubmit: addFirstMatch)

                if isSearchFocused || !search.isEmpty {
                    optionList
                }
            }
        }
    }

    /// One pick: what it is, the role on it, and a way off the list.
    private func row(_ option: (id: EntityID, title: String, color: Color, isPlaceholder: Bool))
        -> some View
    {
        HStack(spacing: Theme.Spacing.small) {
            Pill(option.title, color: option.color, icon: "xmark") {
                selected.remove(option.id)
            }

            Spacer(minLength: 0)

            RoleField(
                role: Binding(
                    get: { roles[option.id] ?? "" },
                    set: { roles[option.id] = $0 }))
        }
    }

    private var optionList: some View {
        ScrollView {
            VStack(spacing: 1) {
                if matches.isEmpty {
                    Text("No matches")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.Spacing.small)
                        .padding(.vertical, 5)
                } else {
                    ForEach(matches, id: \.id) { option in
                        SidebarRow(
                            title: option.title,
                            dotColor: option.color,
                            isSelected: false,
                            isPlaceholder: option.isPlaceholder
                        ) {
                            selected.insert(option.id)
                            search = ""
                        }
                    }
                }
            }
            .padding(Theme.Spacing.xs)
        }
        .frame(maxHeight: 108)
        .background(Theme.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium)
                .stroke(Theme.border, lineWidth: Theme.hairline)
        )
    }

    /// In `options` order, so rows don't reshuffle as roles are typed.
    private var selectedOptions: [(id: EntityID, title: String, color: Color, isPlaceholder: Bool)] {
        options.filter { selected.contains($0.id) }
    }

    private var matches: [(id: EntityID, title: String, color: Color, isPlaceholder: Bool)] {
        options.filter {
            !selected.contains($0.id)
                && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))
        }
    }

    private func addFirstMatch() {
        guard let first = matches.first else { return }
        selected.insert(first.id)
        search = ""
    }
}

/// Staffs a project from the project's side.
struct ParticipantsField: View {
    let people: [Person]
    @Binding var selected: Set<EntityID>
    @Binding var roles: [EntityID: String]

    var body: some View {
        RoleAssignmentField(
            options: people.map {
                ($0.id, $0.displayName, Theme.color(for: $0), $0.placeholder)
            },
            label: "People",
            prompt: "Search people",
            emptyMessage: "No people in the vault yet — add some and you can staff this here.",
            selected: $selected,
            roles: $roles)
    }
}

/// The same memberships from the person's side.
struct ProjectMembershipsField: View {
    let projects: [Project]
    @Binding var selected: Set<EntityID>
    @Binding var roles: [EntityID: String]

    var body: some View {
        RoleAssignmentField(
            options: projects.map { ($0.id, $0.displayName, Theme.projectColor, false) },
            label: "Projects",
            prompt: "Search projects",
            emptyMessage: "No projects in the vault yet.",
            selected: $selected,
            roles: $roles)
    }
}

/// A role on a membership: plain free text, nothing else.
///
/// No suggestion menu, unlike ``LabelField``. A relation label is a closed vocabulary you
/// reuse across the whole vault, but a role is what one person does on one project, and it
/// is nearly always typed fresh — the chevron sat there promising a shortcut that mostly
/// offered someone else's job title. The "Role" header above the column says what the field
/// is for, which is what the chevron was really doing.
struct RoleField: View {
    @Binding var role: String

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $role)
            .textFieldStyle(.plain)
            .font(Theme.Font.body)
            .foregroundStyle(Theme.textNormal)
            .placeholder("Role", isVisible: role.isEmpty)
            .focused($isFocused)
            .frame(width: Theme.Width.roleField)
            .padding(.horizontal, Theme.Spacing.small)
            .padding(.vertical, 4)
            .background(Theme.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium)
                    .stroke(
                        isFocused ? Theme.accent : Theme.border,
                        lineWidth: Theme.hairline)
            )
            // The border, the padding and the placeholder are all drawn *outside* the
            // `TextField` itself, so only a click on the glyph line reached the input —
            // the field read as dead. Claiming the whole drawn box and focusing it by
            // hand makes every part of what looks like the field behave like it.
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
            .onTapGesture { isFocused = true }
            .textCursor()
    }
}

/// The markdown body below the frontmatter. Titled per entity kind: what you write
/// about a person is a private note, while a project's prose describes the work itself,
/// so the same field is labelled "Description" there.
struct NotesField: View {
    @Binding var text: String
    var title: String = "Notes"
    /// Shown dimmed while the body is empty, so it matches the single-line fields above it.
    var placeholder: String = "Anything worth remembering…"

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textMuted)
            TextEditor(text: $text)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textNormal)
                .scrollContentBackground(.hidden)
                // Inset matches the gap AppKit leaves between a text view's edge and its
                // first glyph, so the placeholder sits exactly where the caret does.
                .placeholder(
                    placeholder, isVisible: text.isEmpty, alignment: .topLeading,
                    inset: Theme.Spacing.xs)
                .padding(Theme.Spacing.small)
                .frame(height: 80)
                .background(Theme.bgPrimary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.medium)
                        .stroke(Theme.border, lineWidth: Theme.hairline)
                )
        }
    }
}
