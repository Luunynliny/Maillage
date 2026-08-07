import SwiftUI

/// Three-pane shell: sidebar, graph, detail.
///
/// Owns the selection and the currently presented editor so the sidebar, graph and
/// detail pane all stay in sync through a single piece of state.
public struct RootView: View {
    @Environment(VaultStore.self) private var store

    @State private var selection: EntityID?
    @State private var editorRequest: EditorRequest?
    @State private var isPaletteVisible = false
    @State private var isPickingVault = false
    /// Whether the detail column is showing. The leading column gets a toggle from
    /// `NavigationSplitView` for free, but the detail column gets none —
    /// `NavigationSplitViewVisibility` only ever collapses columns from the left — so
    /// hiding it is this view's own state. See ``detailToggle``.
    @State private var isDetailVisible = true

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, editorRequest: $editorRequest)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
        } content: {
            CenterPane(selection: $selection, editorRequest: $editorRequest)
                .navigationSplitViewColumnWidth(min: 320, ideal: 520)
        } detail: {
            if isDetailVisible {
                DetailView(selection: $selection, editorRequest: $editorRequest)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 560)
            } else {
                // Width zero rather than an absent column: the `detail` closure has to
                // return something, and a collapsed column hands its width to the centre
                // pane, which is what makes the graph grow into the freed space.
                Color.clear.navigationSplitViewColumnWidth(0)
            }
        }
        .navigationTitle("")
        .toolbar { detailToggle }
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

    // MARK: Detail toggle

    /// Hides and shows the detail column, mirroring the sidebar toggle AppKit installs at
    /// the leading edge.
    ///
    /// Deliberately the same `sidebar.right` glyph Xcode and Mail use for their inspectors,
    /// and pinned to `.primaryAction` so it lands at the trailing edge — the two toggles then
    /// sit at opposite ends of the toolbar, each next to the pane it controls.
    @ToolbarContentBuilder
    private var detailToggle: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                isDetailVisible.toggle()
            } label: {
                Image(systemName: "sidebar.right")
            }
            .help(isDetailVisible ? "Hide details" : "Show details")
            .clickableCursor()
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

/// Lets the app's ⌘N menu command reach the window that owns `editorRequest`.
public struct EditorRequestFocusKey: FocusedValueKey {
    public typealias Value = Binding<EditorRequest?>
}

/// Same idea for ⌘K.
public struct PaletteFocusKey: FocusedValueKey {
    public typealias Value = Binding<Bool>
}

/// Same idea for ⌥⌘0, the detail column's toggle.
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

