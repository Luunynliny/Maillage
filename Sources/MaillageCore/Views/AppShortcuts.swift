import SwiftUI

/// One keyboard command the app offers: what it does, which key rings it, and how that key
/// prints in a menu.
///
/// The single source of truth for both ends of a shortcut. `MaillageApp`'s `.commands` builds its
/// menu items from these values, and the sidebar's ``ShortcutsHint`` lists the same ones — so a
/// key can't be changed in the menu while the hint keeps advertising the old one, which is the
/// one failure a second hardcoded list guarantees eventually.
///
/// `character` and `modifiers` rather than a `KeyEquivalent`: the menu needs the SwiftUI value,
/// the hint needs the glyphs, and a stored letter is comparable — `KeyEquivalent` is not even
/// `Equatable`, so a test couldn't check that two commands don't claim the same keystroke.
/// `Equatable` but not `Hashable`, because `EventModifiers` is an `OptionSet` and stops at
/// `Equatable`; `Identifiable` is what `ForEach` in ``ShortcutsHint`` actually needs.
public struct AppShortcut: Identifiable, Equatable, Sendable {
    public let id: String
    /// Phrased as the menu item is, title case included — the hint is read as a list of the
    /// commands in the menu bar, so it should name them the same way.
    public let title: String
    public let character: Character
    public let modifiers: EventModifiers
    /// Whether invoking it opens a sheet, which is what the trailing ellipsis in a menu promises.
    public let opensSheet: Bool

    public init(
        id: String,
        title: String,
        character: Character,
        modifiers: EventModifiers,
        opensSheet: Bool = false
    ) {
        self.id = id
        self.title = title
        self.character = character
        self.modifiers = modifiers
        self.opensSheet = opensSheet
    }

    /// For `.keyboardShortcut(_:modifiers:)`.
    public var keyEquivalent: KeyEquivalent { KeyEquivalent(character) }

    /// The menu item's label: "New Person…" for the ones that open a sheet.
    public var menuTitle: String { opensSheet ? title + "…" : title }

    /// The glyphs macOS prints beside a menu item, in the order it prints them — ⌃⌥⇧⌘ then the
    /// key, whatever order the modifiers were declared in.
    public var display: String {
        var glyphs = ""
        if modifiers.contains(.control) { glyphs += "⌃" }
        if modifiers.contains(.option) { glyphs += "⌥" }
        if modifiers.contains(.shift) { glyphs += "⇧" }
        if modifiers.contains(.command) { glyphs += "⌘" }
        return glyphs + String(character).uppercased()
    }
}

extension AppShortcut {
    public static let newPerson = AppShortcut(
        id: "new-person", title: "New Person", character: "n", modifiers: .command,
        opensSheet: true)

    public static let newPlaceholder = AppShortcut(
        id: "new-placeholder", title: "New Unnamed Person", character: "n",
        modifiers: [.command, .shift], opensSheet: true)

    public static let newOrganization = AppShortcut(
        id: "new-organization", title: "New Organization", character: "o",
        modifiers: [.command, .shift], opensSheet: true)

    public static let newProject = AppShortcut(
        id: "new-project", title: "New Project", character: "p",
        modifiers: [.command, .shift], opensSheet: true)

    public static let palette = AppShortcut(
        id: "palette", title: "Jump to Anything", character: "k", modifiers: .command,
        opensSheet: true)

    /// Titled for the hint, which lists a command once and so can't say "Show" or "Hide"
    /// depending on state the way the menu item does.
    public static let toggleDetails = AppShortcut(
        id: "toggle-details", title: "Show or Hide Details", character: "0",
        modifiers: [.option, .command])

    public static let reload = AppShortcut(
        id: "reload", title: "Reload Vault", character: "r", modifiers: .command)

    /// Every shortcut worth telling someone about, in the order the hint lists them: making
    /// things, then finding them, then what the window shows, then the vault.
    ///
    /// Only what this app declares. ⌃⌘S is deliberately absent even though a sidebar toggle sits
    /// in the toolbar: `NavigationSplitView` gives that button no menu item and no key of its
    /// own, and pressing ⌃⌘S does nothing — a panel whose job is to be trusted cannot list a key
    /// that doesn't ring.
    public static let all: [AppShortcut] = [
        .newPerson,
        .newPlaceholder,
        .newOrganization,
        .newProject,
        .palette,
        .toggleDetails,
        .reload,
    ]
}
