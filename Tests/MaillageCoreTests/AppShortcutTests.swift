import SwiftUI
import Testing

@testable import MaillageCore

/// The shortcut table is read by two places that must agree: the menu bar builds its items from
/// it, and the sidebar's ⓘ lists it. These check the properties a reader of either one relies on.
@Suite("App shortcuts")
struct AppShortcutTests {
    @Test("no two shortcuts claim the same keystroke")
    func keystrokesAreUnique() {
        let keystrokes = AppShortcut.all.map { "\($0.modifiers.rawValue)-\($0.character)" }
        #expect(Set(keystrokes).count == AppShortcut.all.count)
    }

    @Test("the hint lists every shortcut once")
    func listedOnce() {
        let ids = AppShortcut.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("modifiers print in macOS's order, whatever order they were declared in")
    func displayOrder() {
        #expect(AppShortcut.newPerson.display == "⌘N")
        #expect(AppShortcut.newPlaceholder.display == "⇧⌘N")
        #expect(AppShortcut.toggleDetails.display == "⌥⌘0")
    }

    @Test("only the sheet-opening commands get a menu ellipsis")
    func menuEllipsis() {
        #expect(AppShortcut.palette.menuTitle == "Jump to Anything…")
        #expect(AppShortcut.reload.menuTitle == "Reload Vault")
    }

    @Test("every listed shortcut holds a command, not a bare key")
    func everyShortcutIsModified() {
        for shortcut in AppShortcut.all {
            #expect(!shortcut.title.isEmpty)
            // A bare letter would fire while someone is typing in a text field.
            #expect(!shortcut.modifiers.isEmpty)
        }
    }
}
