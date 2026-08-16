import AppKit
import MaillageCore
import SwiftUI

@main
struct MaillageApp: App {
    /// One store per app run — every view reads and writes the vault through it.
    @State private var store = VaultStore()

    /// Forces the process to be an ordinary foreground app.
    ///
    /// Only matters when the binary is run **without** its `.app` bundle, which is what
    /// `swift run` and the SwiftPM scheme in Xcode produce: with no `Info.plist` to read,
    /// AppKit leaves the activation policy at `.prohibited`, and a measurement of the two
    /// cases is unambiguous —
    ///
    /// ```
    /// bundle-less:            policy=2 isActive=false keyWindow=false
    /// bundle-less + .regular: policy=0 isActive=true  keyWindow=true
    /// ```
    ///
    /// An app that is never *active* does not own the cursor, so every `NSCursor.push` in
    /// ``HoverCursor`` is silently discarded and no control shows a hand — the whole
    /// clickable-cursor system looks deleted while being perfectly intact. The same absence
    /// keeps the window from taking key, so text inputs don't focus either.
    ///
    /// Harmless in the bundled `Maillage.app`, whose `Info.plist` already yields `.regular`;
    /// this is a no-op there. Kept so the package build is usable rather than subtly broken,
    /// since `swift run` is the fast path and its failure mode looks like an app bug.
    private let activation = ForegroundActivation()

    /// Runs `setActivationPolicy` once, at init, before any window is ordered front.
    private final class ForegroundActivation {
        init() {
            if NSApplication.shared.activationPolicy() != .regular {
                NSApplication.shared.setActivationPolicy(.regular)
            }
        }
    }

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
