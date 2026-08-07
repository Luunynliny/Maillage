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
            CommandGroup(replacing: .newItem) {
                Button("New Person…") { editorRequest = .newPerson }
                    .keyboardShortcut("n")
                Button("New Unnamed Person…") { editorRequest = .newPlaceholder }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("New Organization…") { editorRequest = .newOrganization }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("New Project…") { editorRequest = .newProject }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            }

            CommandGroup(after: .textEditing) {
                Button("Jump to Anything…") { isPaletteVisible = true }
                    .keyboardShortcut("k")
            }

            // Beside the system's "Show Sidebar" item, since it toggles the pane at the
            // other end of the window. ⌥⌘0 pairs with the ⌃⌘S macOS gives the sidebar.
            CommandGroup(after: .sidebar) {
                Button(isDetailVisible == false ? "Show Details" : "Hide Details") {
                    isDetailVisible?.toggle()
                }
                .keyboardShortcut("0", modifiers: [.option, .command])
                .disabled(isDetailVisible == nil)

                Divider()
                Button("Reload Vault") { store.load() }
                    .keyboardShortcut("r")
                Button("Reveal Vault in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.location.root])
                }
            }
        }
    }
}
