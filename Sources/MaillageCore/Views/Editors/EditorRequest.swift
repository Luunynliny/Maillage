/// What the app should present as a sheet. Driven from the sidebar, detail pane and
/// menu commands so there is a single place that decides which editor is open.
public enum EditorRequest: Identifiable, Hashable {
    case newPerson
    case newPlaceholder
    case newOrganization
    case newProject
    /// The sidebar's Meetings "+". There is no `MeetingEditor` yet — a meeting is created by
    /// recording one, which a later phase wires up here — so this currently opens a short
    /// explanation rather than a sheet that edits anything. See ``RootView``.
    case newMeeting
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
        case .newMeeting: "new-meeting"
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
        case .meeting: .newMeeting
        }
    }
}
