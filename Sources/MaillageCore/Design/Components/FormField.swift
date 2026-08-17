import SwiftUI

/// Draws `text` dimmed behind an input while it is empty.
///
/// AppKit's plain `TextField` renders both its `title` and its `prompt:` in the field's own
/// colour, so `Theme.textNormal` made "Filter" indistinguishable from a typed "Mar". The
/// field is therefore given no placeholder of its own and this sits underneath it, which
/// puts the colour under our control. Not hit-testable, so the click still lands in the text.
struct PlaceholderText: ViewModifier {
    let text: String
    let isVisible: Bool
    let font: Font
    /// `.leading` for a single-line field; `.topLeading` for a `TextEditor`, whose caret
    /// starts at the top rather than centred.
    let alignment: Alignment
    /// Nudge away from `alignment`, for inputs that inset their own text.
    let inset: CGFloat

    func body(content: Content) -> some View {
        content.background(alignment: alignment) {
            if isVisible {
                Text(text)
                    .font(font)
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
                    .allowsHitTesting(false)
                    .padding(inset)
            }
        }
    }
}

extension View {
    /// Shows dimmed `text` behind this input while `isVisible`. See ``PlaceholderText``.
    func placeholder(
        _ text: String, isVisible: Bool, font: Font = Theme.Font.body,
        alignment: Alignment = .leading, inset: CGFloat = 0
    ) -> some View {
        modifier(
            PlaceholderText(
                text: text, isVisible: isVisible, font: font, alignment: alignment,
                inset: inset))
    }
}

/// Labelled text input used across the editors.
public struct FormField: View {
    private let label: String
    private let placeholder: String
    @Binding private var text: String

    public init(_ label: String, placeholder: String = "", text: Binding<String>) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textMuted)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textNormal)
                .placeholder(placeholder, isVisible: text.isEmpty)
                .padding(.horizontal, Theme.Spacing.small)
                .padding(.vertical, 6)
                .background(Theme.bgPrimary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.medium)
                        .stroke(Theme.border, lineWidth: Theme.hairline)
                )
                .textCursor()
        }
    }
}
