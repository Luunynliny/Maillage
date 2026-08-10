import SwiftUI

/// The ⓘ beside the app's name, which lists every keyboard shortcut while the pointer is on it.
///
/// A menu bar already holds all of these, but only one menu at a time and only while it's pulled
/// down — so learning the second shortcut means forgetting where the first one was. The list is
/// built from ``AppShortcut/all``, the same values `MaillageApp` declares its menu items from, so
/// what it advertises is what the keys actually do.
///
/// Hover, not click: the pointer is already crossing the title band on its way to the vault, and
/// this is a reference card rather than a place to be. So the glyph installs no cursor of its own
/// and no gesture — it is a label inside a band that is clickable end to end, and it keeps that
/// band's hand and that band's action. Swallowing the click instead would have carved a dead
/// patch out of the one target that goes back to the overview, to protect a panel that hovering
/// brings straight back.
///
/// A popover rather than a `.help` tooltip: the panel is read as two columns, a command against
/// its keys, and a tooltip is one run of text that can't hold that alignment. It's also anchored
/// `.trailing` so the panel opens *away* from the glyph, leaving the pointer over the icon —
/// a popover under the pointer would take the hover that is keeping it open.
struct ShortcutsHint: View {
    @State private var isHoveringIcon = false
    @State private var isHoveringPanel = false

    var body: some View {
        Image(systemName: "info.circle")
            .font(Theme.Font.body)
            .foregroundStyle(isHoveringIcon ? Theme.textNormal : Theme.textFaint)
            // A 13pt glyph is a mean thing to ask someone to hover onto, so pad it out to a
            // target and hover-test the padded box. Before the popover, so it anchors to the
            // same square rather than to the glyph inside it.
            .padding(Theme.Spacing.xs)
            .contentShape(Rectangle())
            .onHover { isHoveringIcon = $0 }
            .popover(isPresented: isShowing, arrowEdge: .trailing) {
                panel
            }
    }

    /// Open while either the glyph or the panel is hovered. The panel counts because the pointer
    /// crosses the arrow between the two, and a gap in the hover there would close what someone
    /// is in the middle of reading.
    ///
    /// Read-only as a binding: `.popover` needs one it can set on dismissal, and a click outside
    /// dismisses it — which is correct, and taking that write is what stops the hover state from
    /// immediately reopening a panel someone just dismissed.
    private var isShowing: Binding<Bool> {
        Binding(
            get: { isHoveringIcon || isHoveringPanel },
            set: { isNowShowing in
                guard !isNowShowing else { return }
                isHoveringIcon = false
                isHoveringPanel = false
            })
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            SectionHeader("Shortcuts")

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(AppShortcut.all) { shortcut in
                    HStack(spacing: Theme.Spacing.small) {
                        Text(shortcut.title)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.textMuted)
                            .lineLimit(1)
                        Spacer(minLength: Theme.Spacing.small)
                        // Monospaced so the keys line up down the right-hand column: the panel
                        // is scanned for a key as often as for a command.
                        Text(shortcut.display)
                            .font(Theme.Font.mono)
                            .foregroundStyle(Theme.textNormal)
                    }
                }
            }
        }
        .padding(Theme.Spacing.medium)
        .frame(width: Theme.Width.shortcutsHint, alignment: .leading)
        // A popover draws its own material, which is a lighter grey than this app's surfaces;
        // `ignoresSafeAreaEdges` is what lets ours reach the arrow and the corners too.
        .background(Theme.bgSurface, ignoresSafeAreaEdges: .all)
        .onHover { isHoveringPanel = $0 }
    }
}
