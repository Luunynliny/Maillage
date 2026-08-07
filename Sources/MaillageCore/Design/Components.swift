import AppKit
import SwiftUI

// MARK: - Cursor

/// Swaps the cursor while the pointer is inside this view.
///
/// AppKit only changes the cursor over views that install a tracking area, and a
/// `.buttonStyle(.plain)` button installs none — so every control in this file looked inert
/// under the pointer, and a text box that draws its own border still showed an arrow.
///
/// `push`/`pop` rather than `set`: `set` is undone by the next tracking-area update, so the
/// cursor flickers back to an arrow while the pointer is still inside. The pair has to stay
/// balanced, hence `isPushed` — a second hover-in without an intervening hover-out would
/// otherwise stack pushes that never unwind. `onDisappear` covers a control that vanishes
/// while hovered, which would leave the wrong cursor stuck app-wide.
struct HoverCursor: ViewModifier {
    let cursor: NSCursor
    let isActive: Bool

    @State private var isPushed = false

    func body(content: Content) -> some View {
        content
            .onHover { isInside in
                if isInside, isActive {
                    guard !isPushed else { return }
                    isPushed = true
                    cursor.push()
                } else {
                    guard isPushed else { return }
                    isPushed = false
                    NSCursor.pop()
                }
            }
            .onChange(of: isActive) {
                // A button disabled under the pointer has to give the hand back.
                guard !isActive, isPushed else { return }
                isPushed = false
                NSCursor.pop()
            }
            .onDisappear {
                guard isPushed else { return }
                isPushed = false
                NSCursor.pop()
            }
    }
}

extension View {
    /// A pointing hand over anything that responds to a click.
    ///
    /// Applied inside the controls themselves rather than at each use site, so a new button
    /// is clickable-looking by construction and no caller has to remember. `isActive` is for
    /// controls that are only sometimes clickable — a disabled button or an action-less pill
    /// must keep the arrow, since the hand would promise a click that does nothing.
    func clickableCursor(_ isActive: Bool = true) -> some View {
        modifier(HoverCursor(cursor: .pointingHand, isActive: isActive))
    }

    /// An I-beam over a text input's whole drawn box, including the padding around the
    /// glyphs — the border is what reads as "type here", so the cursor has to agree with it.
    func textCursor() -> some View {
        modifier(HoverCursor(cursor: .iBeam, isActive: true))
    }
}

// MARK: - Card

/// A raised surface with a hairline border — Obsidian uses borders rather than
/// shadows to separate content.
public struct Card<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            content
        }
        .padding(Theme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.large)
                .stroke(Theme.border, lineWidth: Theme.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
    }
}

// MARK: - Pill

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

// MARK: - Sidebar row

/// A single sidebar entry with a kind-coloured dot, matching Obsidian's file rows.
public struct SidebarRow: View {
    private let title: String
    private let dotColor: Color
    private let isSelected: Bool
    private let isPlaceholder: Bool
    private let action: () -> Void

    @State private var isHovering = false

    public init(
        title: String,
        dotColor: Color,
        isSelected: Bool,
        isPlaceholder: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.dotColor = dotColor
        self.isSelected = isSelected
        self.isPlaceholder = isPlaceholder
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.small) {
                // A hollow dot signals a placeholder whose name is still unknown.
                Circle()
                    .strokeBorder(dotColor, lineWidth: isPlaceholder ? 1.5 : 0)
                    .background(
                        Circle().fill(isPlaceholder ? Color.clear : dotColor)
                    )
                    .frame(width: Theme.entityDot, height: Theme.entityDot)

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
        .onHover { isHovering = $0 }
        .clickableCursor()
    }

    private var rowBackground: Color {
        if isSelected { return Theme.accent.opacity(0.18) }
        if isHovering { return Theme.bgHover }
        return .clear
    }
}

// MARK: - Section header

/// Small uppercase label that groups sidebar and detail sections.
public struct SectionHeader: View {
    private let title: String
    private let trailing: String?

    public init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    public var body: some View {
        HStack {
            Text(title.uppercased())
                .font(Theme.Font.sectionHeader)
                .tracking(0.6)
                .foregroundStyle(Theme.textFaint)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textFaint)
            }
        }
    }
}

// MARK: - Disclosure chevron

/// The triangle that says whether a collapsible section is open.
///
/// One glyph rotated rather than two symbols swapped, so the turn animates and the arrow is
/// visibly the *same* arrow throughout — swapping `chevron.right` for `chevron.down` cuts
/// instead, which reads as a different control appearing.
///
/// Sized to ``Theme/Font/sectionHeader`` and drawn in ``Theme/textFaint``, matching the
/// ``SectionHeader`` it sits beside: the chevron is punctuation on that label, not a control
/// competing with it for attention. Deliberately not a `DisclosureGroup` — that brings
/// AppKit's own label styling and indentation, which don't match this sidebar.
public struct DisclosureChevron: View {
    private let isExpanded: Bool

    public init(isExpanded: Bool) {
        self.isExpanded = isExpanded
    }

    public var body: some View {
        Image(systemName: "chevron.right")
            .font(Theme.Font.sectionHeader)
            .foregroundStyle(Theme.textFaint)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            // Fixed square: rotating a non-square glyph changes the width it claims, which
            // would shove the section title sideways on every toggle.
            .frame(width: Theme.chevron, height: Theme.chevron)
    }
}

// MARK: - Placeholder

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

// MARK: - Form field

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

// MARK: - Toggle field

/// A switch with a label and a line explaining what turning it on does.
///
/// The explanation is part of the control rather than optional chrome: a switch in a form
/// changes what the rest of the form means, which a bare label can't convey.
public struct ToggleField: View {
    private let label: String
    private let caption: String
    @Binding private var isOn: Bool

    public init(_ label: String, caption: String, isOn: Binding<Bool>) {
        self.label = label
        self.caption = caption
        self._isOn = isOn
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(label)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textNormal)
                Text(caption)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .tint(Theme.accent)
    }
}

// MARK: - Search field

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

// MARK: - Buttons

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
        // never by tabbing — the keyboard route to creating something is ⌘N.
        .focusable(false)
        .onHover { isHovering = $0 }
        .clickableCursor()
        .help(help)
    }
}

// MARK: - Empty state

public struct EmptyStateView: View {
    private let icon: String
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textFaint)
            Text(title)
                .font(Theme.Font.heading)
                .foregroundStyle(Theme.textNormal)
            Text(message)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let actionTitle, let action {
                PrimaryButton(actionTitle, action: action)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgPrimary)
    }
}

// MARK: - Key/value row

/// One line of entity metadata, e.g. `Email  marie@example.com`. The label sits in a
/// fixed-width column so stacked rows align — see ``MetadataList``.
public struct MetadataRow: View {
    private let label: String
    private let value: String
    private let isMonospaced: Bool

    public init(_ label: String, value: String, isMonospaced: Bool = false) {
        self.label = label
        self.value = value
        self.isMonospaced = isMonospaced
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textFaint)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(isMonospaced ? Theme.Font.mono : Theme.Font.body)
                .foregroundStyle(Theme.textNormal)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Flow layout

/// Minimal flow layout — SwiftUI has no built-in wrapping HStack.
public struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    public func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    public func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Metadata list

/// An entity's short facts, one per line with the labels in a column:
///
/// ```
/// Role    Head of Engineering
/// Email   marie@example.com
/// Added   2026-08-06
/// ```
///
/// One fact per row rather than a wrapping single line: values are read by scanning down
/// the label column, and a run-on line reflows unpredictably as the pane is resized, so
/// `Added` lands in a different place for every entity. Rows are ``MetadataRow``, so this
/// and the vault picker render key/value pairs identically.
///
/// Sized to its content, unlike ``Card``, which stretches to the full pane and turns two
/// short values into a conspicuous box. Use this in the detail pane, where the metadata
/// should sit quietly under the title; ``Card`` is for surfaces that need to read as a panel.
public struct MetadataList: View {
    /// One label/value pair. `isMonospaced` is for ids and emails.
    public struct Item: Identifiable {
        let label: String
        let value: String
        let isMonospaced: Bool

        public var id: String { label }

        public init(_ label: String, value: String, isMonospaced: Bool = false) {
            self.label = label
            self.value = value
            self.isMonospaced = isMonospaced
        }
    }

    private let items: [Item]

    public init(_ items: [Item]) {
        self.items = items
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(items) { item in
                MetadataRow(item.label, value: item.value, isMonospaced: item.isMonospaced)
            }
        }
    }
}
