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
        // Menu items only, with no `keyboardShortcut` on any of them. The app had a full set of
        // key equivalents and they were removed deliberately: the shortcuts didn't work in
        // practice, and a key that is advertised — in a menu item's right-hand column or
        // anywhere else — and then doesn't fire is worse than no key at all, because it teaches
        // someone a gesture and then makes them doubt their own keyboard.
        //
        // So these menus are the only route to these actions, alongside the clicks in the UI:
        // the sidebar's "+" per section, the centre pane's pencil, its chevron for the details.
        // Every one of them is reachable by pointer, which is why dropping the keys costs no
        // function.
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Person…") { editorRequest = .newPerson }
                Button("New Unnamed Person…") { editorRequest = .newPlaceholder }
                Divider()
                Button("New Organization…") { editorRequest = .newOrganization }
                Button("New Project…") { editorRequest = .newProject }
            }

            CommandGroup(after: .textEditing) {
                Button("Jump to Anything…") { isPaletteVisible = true }
            }

            // Beside the system's "Show Sidebar" item: both reveal a body of information the
            // window is otherwise hiding. Kept even though the details now fold out of the
            // centre pane's own header rather than being a column, because a menu route
            // shouldn't disappear because the geometry changed.
            CommandGroup(after: .sidebar) {
                // Named for the state it will produce, which a menu item can do because it can
                // ask the focused window what that state currently is.
                Button(isDetailVisible == false ? "Show Details" : "Hide Details") {
                    isDetailVisible?.toggle()
                }
                .disabled(isDetailVisible == nil)

                Divider()
                Button("Reload Vault") { store.load() }
                Button("Reveal Vault in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.location.root])
                }
            }
        }
    }
}
