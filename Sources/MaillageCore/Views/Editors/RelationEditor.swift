import SwiftUI

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
                                        kind: .person,
                                        id: person.id,
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
            resolvedTarget =
                store.createPerson(
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
