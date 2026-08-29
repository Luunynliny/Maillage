import SwiftUI

/// A single sidebar entry led by its ``EntityAvatar``, matching Obsidian's file rows.
///
/// Identified by `kind` and `id` rather than handed a colour, because the avatar has to look the
/// entity up to know whether it has a logo. Every list that reuses this row — the sidebar, the
/// pickers in `Views/Editors/` — gains logos from that one change.
public struct SidebarRow: View {
    private let title: String
    private let kind: EntityKind
    private let id: EntityID
    private let isSelected: Bool
    private let isPlaceholder: Bool
    private let action: () -> Void

    @State private var isHovering = false

    public init(
        title: String,
        kind: EntityKind,
        id: EntityID,
        isSelected: Bool,
        isPlaceholder: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.kind = kind
        self.id = id
        self.isSelected = isSelected
        self.isPlaceholder = isPlaceholder
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.small) {
                EntityAvatar(
                    kind: kind, id: id,
                    size: Theme.Avatar.row,
                    isPlaceholder: isPlaceholder)

                Text(title)
                    .font(Theme.Font.body)
                    .foregroundStyle(isSelected ? Theme.textNormal : Theme.textMuted)
                    .italic(isPlaceholder)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.small)
            .padding(.vertical, 5)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // No focus ring. Selection in this sidebar is drawn by `rowBackground`, and AppKit's
        // blue ring on whichever row happens to be first responder is a second, competing
        // claim — on launch it landed on the top row while a different row was actually
        // selected, so two rows looked chosen. Rows are reached by clicking, or through the
        // command palette.
        .focusable(false)
        .onHover { isHovering = $0 }
        .clickableCursor()
    }

    private var rowBackground: Color {
        if isSelected { return Theme.accent.opacity(0.18) }
        if isHovering { return Theme.bgHover }
        return .clear
    }
}
