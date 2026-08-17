import SwiftUI

public struct PrimaryButton: View {
    private let title: String
    private let action: () -> Void
    private let isEnabled: Bool

    @State private var isHovering = false

    public init(_ title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Font.body.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.medium)
                .padding(.vertical, 6)
                .background(isHovering && isEnabled ? Theme.accentHover : Theme.accent)
                .opacity(isEnabled ? 1 : 0.4)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
        .clickableCursor(isEnabled)
    }
}

public struct SecondaryButton: View {
    private let title: String
    private let icon: String?
    private let action: () -> Void

    @State private var isHovering = false

    public init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                if let icon { Image(systemName: icon).font(Theme.Font.caption) }
                Text(title).font(Theme.Font.body)
            }
            .foregroundStyle(Theme.textNormal)
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, 6)
            .background(isHovering ? Theme.bgHover : Theme.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium)
                    .stroke(Theme.border, lineWidth: Theme.hairline)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .clickableCursor()
    }
}

/// `SecondaryButton` with the label dropped: the same bordered box, squared off, so a
/// lone icon still reads as something you can click. `help` supplies the missing word.
public struct IconButton: View {
    private let icon: String
    private let help: String
    private let action: () -> Void

    @State private var isHovering = false

    public init(_ icon: String, help: String, action: @escaping () -> Void) {
        self.icon = icon
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(Theme.Font.body)
                .foregroundStyle(isHovering ? Theme.textNormal : Theme.textMuted)
                .frame(width: 22, height: 22)
                .background(isHovering ? Theme.bgHover : Theme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.medium)
                        .stroke(Theme.border, lineWidth: Theme.hairline)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .clickableCursor()
        .help(help)
    }
}

/// Bare "+" for creating something inside a section.
///
/// Unlike ``IconButton`` it draws no box: a section header is a quiet label, and a bordered
/// button beside it would outweigh the heading it belongs to.
public struct AddButton: View {
    private let help: String
    private let action: () -> Void

    @State private var isHovering = false

    public init(help: String, action: @escaping () -> Void) {
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "plus.circle")
                .font(Theme.Font.body)
                .foregroundStyle(isHovering ? Theme.textNormal : Theme.textMuted)
                // The glyph alone is a small target, so take the whole frame.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // No focus ring: this is the first focusable control in the sidebar, so on launch
        // AppKit gave it a blue ring that read as a selected row. It's reached by clicking,
        // never by tabbing — the other route to creating something is the File menu.
        .focusable(false)
        .onHover { isHovering = $0 }
        .clickableCursor()
        .help(help)
    }
}
