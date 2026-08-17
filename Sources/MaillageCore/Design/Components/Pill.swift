import SwiftUI

/// A small tappable token used for links to other entities and for relation labels.
public struct Pill: View {
    private let text: String
    private let color: Color
    private let icon: String?
    private let action: (() -> Void)?

    @State private var isHovering = false

    public init(
        _ text: String, color: Color = Theme.accent, icon: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.text = text
        self.color = color
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        let label = HStack(spacing: Theme.Spacing.xs) {
            if let icon {
                Image(systemName: icon).font(Theme.Font.caption)
            }
            Text(text).font(Theme.Font.body)
        }
        .padding(.horizontal, Theme.Spacing.small)
        .padding(.vertical, Theme.Spacing.xs)
        .foregroundStyle(color)
        .background(color.opacity(isHovering && action != nil ? 0.22 : 0.13))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: Theme.hairline))

        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
                .onHover { isHovering = $0 }
                .clickableCursor()
        } else {
            // No action, no hand: a pill is also used as a plain read-only tag.
            label
        }
    }
}
