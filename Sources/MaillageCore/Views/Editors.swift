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
    /// True when creating an unnamed placeholder.
    let isPlaceholder: Bool
    /// True when filling in the name of an existing placeholder.
    let isResolving: Bool
    var onSaved: (EntityID) -> Void = { _ in }

    @State private var firstname = ""
    @State private var lastname = ""
    @State private var email = ""
    @State private var descriptor = ""
    @State private var notes = ""
    @State private var organizations: Set<EntityID> = []
    @State private var projects: Set<EntityID> = []

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
                if isPlaceholder {
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

                MultiSelectField(
                    label: "Organizations",
                    options: store.allOrganizations.map { ($0.id, $0.displayName) },
                    selected: $organizations,
                    color: Theme.organizationColor,
                    prompt: "Search organizations")

                MultiSelectField(
                    label: "Projects",
                    options: store.allProjects.map { ($0.id, $0.displayName) },
                    selected: $projects,
                    color: Theme.projectColor,
                    prompt: "Search projects")

                NotesField(text: $notes)
            }
        }
        .onAppear(perform: populate)
    }

    private var title: String {
        if isResolving { return "Add a name" }
        if let existing { return "Edit \(existing.displayName)" }
        return isPlaceholder ? "New unnamed person" : "New person"
    }

    private var subtitle: String? {
        if isResolving {
            return
                "Filling in the name renames the file and updates every link pointing at this person."
        }
        if isPlaceholder {
            return
                "For someone you've heard about but can't name yet. You can add the real name later."
        }
        return nil
    }

    private var isValid: Bool {
        if isPlaceholder { return descriptor.nilIfBlank != nil }
        return firstname.nilIfBlank != nil || lastname.nilIfBlank != nil
    }

    private func populate() {
        guard let existing else { return }
        firstname = existing.firstname ?? ""
        lastname = existing.lastname ?? ""
        email = existing.email ?? ""
        descriptor = existing.descriptor ?? ""
        notes = existing.body
        organizations = Set(existing.organizations.map(\.id))
        projects = Set(existing.projects.map(\.id))
    }

    private func save() {
        let orgLinks = organizations.sorted().map(Wikilink.init)
        let projectLinks = projects.sorted().map(Wikilink.init)

        if var person = existing {
            if isResolving {
                person.organizations = orgLinks
                person.projects = projectLinks
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
                person.descriptor = descriptor.nilIfBlank
                person.organizations = orgLinks
                person.projects = projectLinks
                person.body = notes
                if store.update(person) { onSaved(person.id) }
            }
        } else if let created = store.createPerson(
            firstname: firstname,
            lastname: lastname,
            email: email,
            descriptor: descriptor,
            placeholder: isPlaceholder,
            organizations: orgLinks,
            projects: projectLinks,
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
    @State private var organizations: Set<EntityID> = []
    @State private var notes = ""

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

                MultiSelectField(
                    label: "Organizations",
                    options: store.allOrganizations.map { ($0.id, $0.displayName) },
                    selected: $organizations,
                    color: Theme.organizationColor,
                    prompt: "Search organizations")

                NotesField(text: $notes, title: "Description")
            }
        }
        .onAppear {
            guard let existing else { return }
            name = existing.name
            status = existing.status
            organizations = Set(existing.organizations.map(\.id))
            notes = existing.body
        }
    }

    private func save() {
        let orgLinks = organizations.sorted().map(Wikilink.init)
        if var project = existing {
            project.name = name
            project.status = status
            project.organizations = orgLinks
            project.body = notes
            if store.update(project) { onSaved(project.id) }
        } else if let created = store.createProject(
            name: name, status: status, organizations: orgLinks, body: notes)
        {
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

/// Picks any number of entities, used for org and project membership.
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
        selected.insert(first.id)
        search = ""
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
