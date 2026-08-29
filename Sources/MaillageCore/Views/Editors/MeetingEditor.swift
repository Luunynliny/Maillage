import SwiftUI

/// Edits a finished meeting's organization, project and attendees — the same three fields
/// ``MeetingView``'s recording banner keeps live while a meeting is being recorded, but
/// unreachable once it stops, since that banner disappears with the recording. There is no
/// "new meeting" case here: a meeting is only ever created by recording one.
struct MeetingEditor: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let existing: Meeting
    var onSaved: (EntityID) -> Void = { _ in }

    /// Holds at most one — see the `limit: 1` on its field.
    @State private var organizations: Set<EntityID> = []
    @State private var projects: Set<EntityID> = []
    @State private var attendees: Set<EntityID> = []

    var body: some View {
        EditorSheet(
            title: "Edit \(existing.displayName)",
            onConfirm: save,
            onCancel: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                MultiSelectField(
                    label: "Organization",
                    options: store.allOrganizations.map { ($0.id, $0.displayName) },
                    selected: $organizations,
                    kind: .organization,
                    prompt: "Search organizations",
                    limit: 1)

                MultiSelectField(
                    label: "Project",
                    options: projectOptions,
                    selected: $projects,
                    kind: .project,
                    prompt: "Search projects",
                    limit: 1)

                MultiSelectField(
                    label: "Attendees",
                    options: store.allPeople.map { ($0.id, $0.displayName) },
                    selected: $attendees,
                    kind: .person,
                    prompt: "Search people")
            }
        }
        .onAppear(perform: populate)
        .onChange(of: projects, deriveOrganizationFromProject)
    }

    /// Filtered to the chosen organization so a later project pick can never silently overwrite
    /// it — falls back to every project when no organization is set yet. Mirrors
    /// `MeetingView.projectOptions`.
    private var projectOptions: [(EntityID, String)] {
        guard let organizationID = organizations.first else {
            return store.allProjects.map { ($0.id, $0.displayName) }
        }
        return store.projects(inOrganization: organizationID).map { ($0.id, $0.displayName) }
    }

    /// Organization always follows the chosen project, never the other way around — see
    /// `MeetingView.deriveOrganizationFromProject`.
    private func deriveOrganizationFromProject(_ oldValue: Set<EntityID>, _ newValue: Set<EntityID>)
    {
        guard let projectID = newValue.first,
            let organization = store.allProjects.first(where: { $0.id == projectID })?.organization
        else { return }
        organizations = [organization.id]
    }

    private func populate() {
        organizations = Set(existing.organization.map { [$0.id] } ?? [])
        projects = Set(existing.project.map { [$0.id] } ?? [])
        attendees = Set(existing.attendees.map(\.id))
    }

    private func save() {
        var meeting = existing
        meeting.organization = organizations.first.map(Wikilink.init)
        meeting.project = projects.first.map(Wikilink.init)
        meeting.attendees = attendees.sorted().map(Wikilink.init)
        if store.update(meeting) {
            onSaved(meeting.id)
        }
        dismiss()
    }
}
