import SwiftUI

/// Text input with a magnifier and a clear button, for anywhere the list of things being
/// narrowed is too long to browse: the sidebar filter and the editors' option pickers.
public struct SearchField: View {
    private let placeholder: String
    @Binding private var text: String
    /// Mirrors the inner field's focus outward. `.focused` on this whole view would make
    /// the container focusable instead, swallowing the click that should land in the text.
    private var isFocused: Binding<Bool>?
    private let onSubmit: () -> Void

    @FocusState private var fieldFocus: Bool

    public init(
        _ placeholder: String,
        text: Binding<String>,
        isFocused: Binding<Bool>? = nil,
        onSubmit: @escaping () -> Void = {}
    ) {
        self.placeholder = placeholder
        self._text = text
        self.isFocused = isFocused
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textFaint)

            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textNormal)
                .placeholder(placeholder, isVisible: text.isEmpty)
                .focused($fieldFocus)
                .onSubmit(onSubmit)
                .onChange(of: fieldFocus) { isFocused?.wrappedValue = fieldFocus }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textFaint)
                }
                .buttonStyle(.plain)
                .clickableCursor()
            }
        }
        .padding(.horizontal, Theme.Spacing.small)
        .padding(.vertical, 5)
        .background(Theme.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium)
                .stroke(Theme.border, lineWidth: Theme.hairline)
        )
        // The whole box, magnifier included — anywhere in it, a click means "type here".
        .textCursor()
    }
}
