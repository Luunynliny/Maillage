import SwiftUI

/// An entity's ``EntityAvatar`` beside its name, as a link to it.
///
/// What a ``Pill`` was for a person before logos existed. A pill's capsule and tint were the
/// whole affordance *and* the whole identification, which a 16pt logo does better — but two
/// tinted capsules per row also crowded out the thing next to them, and on a roster the thing
/// next to them is the role, which is what the pane is read for. So the capsule goes and the
/// avatar arrives: more identifying signal, less ink.
///
/// Hover underlines the name rather than washing a background behind it, because these sit in
/// cards and table rows whose own padding a wash would have to agree with — and an underlined
/// link on hover is what Obsidian does with an internal link. ``Pill`` stays for the things that
/// aren't entities: relation labels, and the removable tokens in the editors.
public struct EntityLink: View {
    private let title: String
    private let kind: EntityKind
    private let id: EntityID
    private let size: CGFloat
    private let isPlaceholder: Bool
    private let action: () -> Void

    @State private var isHovering = false

    public init(
        title: String,
        kind: EntityKind,
        id: EntityID,
        size: CGFloat = Theme.Avatar.row,
        isPlaceholder: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.kind = kind
        self.id = id
        self.size = size
        self.isPlaceholder = isPlaceholder
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                EntityAvatar(
                    kind: kind, id: id, size: size, isPlaceholder: isPlaceholder)

                Text(title)
                    .font(Theme.Font.body)
                    .foregroundStyle(isPlaceholder ? Theme.textMuted : Theme.textNormal)
                    .italic(isPlaceholder)
                    .underline(isHovering)
                    // Two lines, not one: a board card is 240pt wide and "Head of Procurement
                    // at Orion" does not fit on a line of it. Truncating a name is worse than
                    // wrapping it when the name is the identification.
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .clickableCursor()
    }
}
