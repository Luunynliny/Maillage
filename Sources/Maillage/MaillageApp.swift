import MaillageCore
import SwiftUI

@main
struct MaillageApp: App {
    /// One store per app run — every view reads and writes the vault through it.
    @State private var store = VaultStore()

    /// Bound from the focused window so menu commands can open its sheets.
    @FocusedBinding(\.editorRequest) private var editorRequest
    @FocusedBinding(\.isPaletteVisible) private var isPaletteVisible
    @FocusedBinding(\.isDetailVisible) private var isDetailVisible

    var body: some Scene {
        WindowGroup("maillage") {
            RootView()
                .environment(store)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowToolbarStyle(.unified)
        .commands {
            // Every item's title and keys come from ``AppShortcut``, which the sidebar's ⓘ also
            // lists — so the panel advertising a shortcut and the item that rings it cannot say
            // different things.
            CommandGroup(replacing: .newItem) {
                command(.newPerson) { editorRequest = .newPerson }
                command(.newPlaceholder) { editorRequest = .newPlaceholder }
                Divider()
                command(.newOrganization) { editorRequest = .newOrganization }
                command(.newProject) { editorRequest = .newProject }
            }

            CommandGroup(after: .textEditing) {
                command(.palette) { isPaletteVisible = true }
            }

            // Beside the system's "Show Sidebar" item: both reveal a body of information the
            // window is otherwise hiding. ⌥⌘0 pairs with the ⌃⌘S macOS gives the sidebar.
            // Kept even though the details now fold out of the centre pane's own header
            // rather than being a column, because the chevron is the only other way in and
            // a keyboard route shouldn't disappear because the geometry changed.
            CommandGroup(after: .sidebar) {
                // Named for the state it will produce, unlike the hint's single entry, which has
                // no window to ask.
                Button(isDetailVisible == false ? "Show Details" : "Hide Details") {
                    isDetailVisible?.toggle()
                }
                .keyboardShortcut(
                    AppShortcut.toggleDetails.keyEquivalent,
                    modifiers: AppShortcut.toggleDetails.modifiers)
                .disabled(isDetailVisible == nil)

                Divider()
                command(.reload) { store.load() }
                Button("Reveal Vault in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.location.root])
                }
            }
        }
    }

    /// A menu item titled and keyed by `shortcut`.
    private func command(_ shortcut: AppShortcut, action: @escaping () -> Void) -> some View {
        Button(shortcut.menuTitle, action: action)
            .keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.modifiers)
    }
}
