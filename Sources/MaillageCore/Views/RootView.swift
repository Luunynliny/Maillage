import SwiftUI

/// Two-pane shell: sidebar and subject.
///
/// Owns the selection and the currently presented editor so the sidebar and the centre pane
/// stay in sync through a single piece of state.
///
/// There is no detail column. What it held now folds out of the centre pane's own title band
/// (``CenterPaneHeader``), directly under the name of the thing it describes. A third column
/// meant the subject's name was drawn twice, side by side, and the graph — the widest thing in
/// the app and the reason it's a desktop app — was permanently squeezed by a pane of metadata
/// that is mostly worth one glance.
public struct RootView: View {
    @Environment(VaultStore.self) private var store

    @State private var selection: EntityID?
    @State private var editorRequest: EditorRequest?
    @State private var isPaletteVisible = false
    @State private var isPickingVault = false
    /// Whether the centre pane's details section is unfolded. Held here rather than in
    /// ``CenterPaneHeader`` so the View menu's Show/Hide Details item can reach it; the header
    /// folds it back shut on every change of subject.
    @State private var isDetailVisible = false

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, editorRequest: $editorRequest)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
        } detail: {
            CenterPane(
                selection: $selection,
                editorRequest: $editorRequest,
                isDetailVisible: $isDetailVisible)
        }
        // Details fold shut on every change of subject. Here rather than in
        // ``CenterPaneHeader``, because switching between kinds swaps the whole centre view for
        // a different one — an `onChange` inside the header would miss exactly that case.
        .onChange(of: selection) { isDetailVisible = false }
        .navigationTitle("")
        .toolbarBackground(Theme.bgSecondary, for: .windowToolbar)
        .background(Theme.bgPrimary)
        .sheet(item: $editorRequest) { request in
            editor(for: request)
        }
        .sheet(isPresented: $isPickingVault) {
            VaultPicker(isPresented: $isPickingVault)
        }
        // A sheet, not an overlay: as an overlay on the split view the palette's text
        // field never became first responder, so it swallowed every keystroke.
        .sheet(isPresented: $isPaletteVisible) {
            CommandPalette(
                isPresented: $isPaletteVisible,
                selection: $selection,
                editorRequest: $editorRequest)
        }
        .onAppear(perform: start)
        .focusedSceneValue(\.editorRequest, $editorRequest)
        .focusedSceneValue(\.isPaletteVisible, $isPaletteVisible)
        .focusedSceneValue(\.isDetailVisible, $isDetailVisible)
        .overlay(alignment: .bottom) {
            if let error = store.lastError {
                errorBanner(error)
            }
        }
    }

    /// A brand-new user picks a folder first; everyone else loads straight in.
    private func start() {
        if store.location.exists {
            store.load()
        } else {
            isPickingVault = true
        }
    }

    // MARK: Sheets

    @ViewBuilder
    private func editor(for request: EditorRequest) -> some View {
        switch request {
        case .newPerson:
            PersonEditor(existing: nil, isPlaceholder: false, isResolving: false) {
                selection = $0
            }

        case .newPlaceholder:
            PersonEditor(existing: nil, isPlaceholder: true, isResolving: false) {
                selection = $0
            }

        case .newOrganization:
            OrganizationEditor(existing: nil) { selection = $0 }

        case .newProject:
            ProjectEditor(existing: nil) { selection = $0 }

        case .newMeeting:
            DismissibleMessage(
                title: "Recording isn't wired up yet",
                message:
                    "A meeting is created by recording it, which arrives in a later phase. "
                    + "For now, add one to the vault by hand — see the meetings/ folder.")

        case .edit(let id):
            switch store.entity(id: id) {
            case .person(let person):
                PersonEditor(
                    existing: person,
                    isPlaceholder: person.placeholder,
                    isResolving: false
                ) { selection = $0 }
            case .organization(let org):
                OrganizationEditor(existing: org) { selection = $0 }
            case .project(let project):
                ProjectEditor(existing: project) { selection = $0 }
            case .meeting:
                // No `MeetingEditor` yet, matching `.newMeeting` above — attendees are set
                // while recording, and nothing else on a meeting is edited in-app so far.
                DismissibleMessage(
                    title: "Meetings aren't edited here",
                    message:
                        "Set attendees while recording. Everything else can be edited by hand "
                        + "in the vault file for now.")
            case nil:
                missingEntitySheet
            }

        case .resolvePlaceholder(let id):
            if case .person(let person) = store.entity(id: id) {
                PersonEditor(existing: person, isPlaceholder: false, isResolving: true) {
                    // Resolving renames the file, so follow the new id.
                    selection = $0
                }
            } else {
                missingEntitySheet
            }

        case .addRelation(let id):
            RelationEditor(sourceID: id)

        case .confirmDelete(let id):
            if let entity = store.entity(id: id) {
                DeleteConfirmation(entity: entity) {
                    if store.delete(kind: entity.kind, id: entity.id), selection == entity.id {
                        selection = nil
                    }
                }
            } else {
                missingEntitySheet
            }
        }
    }

    private var missingEntitySheet: some View {
        DismissibleMessage(
            title: "That entry is gone",
            message: "It was deleted or renamed on disk. Reload the vault to catch up.")
    }

    // MARK: Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Theme.Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.projectColor)
            Text(message)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textNormal)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button {
                store.lastError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textFaint)
            }
            .buttonStyle(.plain)
            .clickableCursor()
        }
        .padding(Theme.Spacing.small)
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium)
                .stroke(Theme.border, lineWidth: Theme.hairline)
        )
        .padding(Theme.Spacing.medium)
        .frame(maxWidth: 520)
    }
}

// MARK: - Delete confirmation

/// Spells out what deleting will break, since deletes also scrub inbound links.
private struct DeleteConfirmation: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let entity: AnyEntity
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Delete \(entity.displayName)?")
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.textNormal)
                Text(consequence)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                SecondaryButton("Cancel") { dismiss() }
                Button("Delete") {
                    onConfirm()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 400)
        .background(Theme.bgSecondary)
    }

    private var consequence: String {
        let inbound = store.backlinks(for: entity.id).count
        var lines = ["The file \(entity.kind.directoryName)/\(entity.id).md will be removed."]
        if inbound > 0 {
            lines.append(
                "\(inbound) relation\(inbound == 1 ? "" : "s") pointing here will also be removed.")
        }
        if case .organization = entity {
            let members = store.members(ofOrganization: entity.id).count
            if members > 0 {
                lines.append("\(members) people will be unlinked from it, but not deleted.")
            }
        }
        if case .project = entity {
            let members = store.members(ofProject: entity.id).count
            if members > 0 {
                lines.append("\(members) people will be unlinked from it, but not deleted.")
            }
        }
        // Meetings never appear in `backlinks(for:)` — nothing links *to* one — so without
        // this, deleting a well-attended person or a project full of meeting notes looked
        // consequence-free right up until the meeting history quietly lost an attendee.
        let meetingCount: Int =
            switch entity {
            case .person: store.meetings(withPerson: entity.id).count
            case .organization: store.meetings(inOrganization: entity.id).count
            case .project: store.meetings(onProject: entity.id).count
            case .meeting: 0
            }
        if meetingCount > 0 {
            lines.append(
                "\(meetingCount) meeting\(meetingCount == 1 ? "" : "s") will no longer reference it, but won't be deleted."
            )
        }
        return lines.joined(separator: " ")
    }
}

private struct DismissibleMessage: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            Text(title)
                .font(Theme.Font.heading)
                .foregroundStyle(Theme.textNormal)
            Text(message)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                PrimaryButton("OK") { dismiss() }
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 380)
        .background(Theme.bgSecondary)
    }
}

// MARK: - Menu plumbing

/// Lets the File menu's New Person item reach the window that owns `editorRequest`.
public struct EditorRequestFocusKey: FocusedValueKey {
    public typealias Value = Binding<EditorRequest?>
}

/// Same idea for Jump to Anything.
public struct PaletteFocusKey: FocusedValueKey {
    public typealias Value = Binding<Bool>
}

/// Same idea for Show/Hide Details.
public struct DetailVisibleFocusKey: FocusedValueKey {
    public typealias Value = Binding<Bool>
}

extension FocusedValues {
    public var editorRequest: Binding<EditorRequest?>? {
        get { self[EditorRequestFocusKey.self] }
        set { self[EditorRequestFocusKey.self] = newValue }
    }

    public var isPaletteVisible: Binding<Bool>? {
        get { self[PaletteFocusKey.self] }
        set { self[PaletteFocusKey.self] = newValue }
    }

    public var isDetailVisible: Binding<Bool>? {
        get { self[DetailVisibleFocusKey.self] }
        set { self[DetailVisibleFocusKey.self] = newValue }
    }
}
