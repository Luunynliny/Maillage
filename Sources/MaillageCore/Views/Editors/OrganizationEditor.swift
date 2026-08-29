import SwiftUI

struct OrganizationEditor: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let existing: Organization?
    var onSaved: (EntityID) -> Void = { _ in }

    @State private var name = ""
    @State private var domain = ""
    @State private var notes = ""
    /// Staged, applied in ``save()`` — see ``LogoChange``.
    @State private var logo: LogoChange = .unchanged

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
                LogoField(kind: .organization, existingID: existing?.id, change: $logo)
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
            if store.update(org) {
                store.apply(logo, kind: .organization, id: org.id)
                onSaved(org.id)
            }
        } else if let created = store.createOrganization(
            name: name, domain: domain, body: notes)
        {
            store.apply(logo, kind: .organization, id: created.id)
            onSaved(created.id)
        }
        dismiss()
    }
}
