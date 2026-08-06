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

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, editorRequest: $editorRequest)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
        } content: {
            GraphView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 320, ideal: 520)
        } detail: {
            DetailView(selection: $selection, editorRequest: $editorRequest)
                .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 560)
        }
        .navigationTitle("")
        .toolbar { toolbar }
        .toolbarBackground(Theme.bgSecondary, for: .windowToolbar)
        .background(Theme.bgPrimary)
        .sheet(item: $editorRequest) { request in
            editor(for: request)
        }
        .sheet(isPresented: $isPickingVault) {
            VaultPicker(isPresented: $isPickingVault)
        }
        .onAppear(perform: start)
        .focusedSceneValue(\.editorRequest, $editorRequest)
        .focusedSceneValue(\.isPaletteVisible, $isPaletteVisible)
        .overlay {
            if isPaletteVisible {
                paletteOverlay
            }
        }
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

    // MARK: Command palette

    private var paletteOverlay: some View {
        ZStack(alignment: .top) {
            // Click-off dismissal, dimming the app behind the palette.
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { isPaletteVisible = false }

            CommandPalette(
                isPresented: $isPaletteVisible,
                selection: $selection,
                editorRequest: $editorRequest
            )
            .padding(.top, 80)
        }
        .transition(.opacity)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                isPaletteVisible = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.textMuted)
            }
            .help("Jump to anything (⌘K)")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                editorRequest = .newPerson
            } label: {
                Image(systemName: "person.badge.plus")
                    .foregroundStyle(Theme.textMuted)
            }
            .help("New person (⌘N)")
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

extension FocusedValues {
    public var editorRequest: Binding<EditorRequest?>? {
        get { self[EditorRequestFocusKey.self] }
        set { self[EditorRequestFocusKey.self] = newValue }
    }

    public var isPaletteVisible: Binding<Bool>? {
        get { self[PaletteFocusKey.self] }
        set { self[PaletteFocusKey.self] = newValue }
    }
}

