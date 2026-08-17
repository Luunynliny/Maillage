import SwiftUI

/// Small leaf fields shared across the editors, none big enough to warrant a file of their own.

/// Names a relation by typing a label, or tapping one already used in the vault.
///
/// There is no preset vocabulary: the labels offered are whatever the person has used
/// before, so this starts bare and grows as they name relationships. Deliberately a plain
/// text field rather than a search box with a dropdown — a magnifier and a list of hits
/// read as a picker, so a brand-new label that matched nothing looked like it couldn't be
/// entered at all. Typing is the primary action here; the pills are the shortcut.
struct LabelField: View {
    @Binding var label: String
    /// Labels already used in the vault, most-used first.
    let known: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            FormField("Label", placeholder: "e.g. manager of", text: $label)

            if !matches.isEmpty {
                Text(label.isEmpty ? "Used before" : "Matching")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textFaint)

                FlowLayout(spacing: Theme.Spacing.xs) {
                    ForEach(matches, id: \.self) { suggestion in
                        Pill(suggestion, color: Theme.accent) { label = suggestion }
                    }
                }
            }
        }
    }

    /// Known labels matching what's typed. Filtered rather than trimmed to an exact match
    /// so the row stays put while typing instead of collapsing under the cursor.
    private var matches: [String] {
        known.filter { label.isEmpty || $0.localizedCaseInsensitiveContains(label) }
    }
}

/// A role on a membership: plain free text, nothing else.
///
/// No suggestion menu, unlike ``LabelField``. A relation label is a closed vocabulary you
/// reuse across the whole vault, but a role is what one person does on one project, and it
/// is nearly always typed fresh — the chevron sat there promising a shortcut that mostly
/// offered someone else's job title. The "Role" header above the column says what the field
/// is for, which is what the chevron was really doing.
struct RoleField: View {
    @Binding var role: String

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $role)
            .textFieldStyle(.plain)
            .font(Theme.Font.body)
            .foregroundStyle(Theme.textNormal)
            .placeholder("Role", isVisible: role.isEmpty)
            .focused($isFocused)
            .frame(width: Theme.Width.roleField)
            .padding(.horizontal, Theme.Spacing.small)
            .padding(.vertical, 4)
            .background(Theme.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium)
                    .stroke(
                        isFocused ? Theme.accent : Theme.border,
                        lineWidth: Theme.hairline)
            )
            // The border, the padding and the placeholder are all drawn *outside* the
            // `TextField` itself, so only a click on the glyph line reached the input —
            // the field read as dead. Claiming the whole drawn box and focusing it by
            // hand makes every part of what looks like the field behave like it.
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
            .onTapGesture { isFocused = true }
            .textCursor()
    }
}

/// The markdown body below the frontmatter. Titled per entity kind: what you write
/// about a person is a private note, while a project's prose describes the work itself,
/// so the same field is labelled "Description" there.
struct NotesField: View {
    @Binding var text: String
    var title: String = "Notes"
    /// Shown dimmed while the body is empty, so it matches the single-line fields above it.
    var placeholder: String = "Anything worth remembering…"

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textMuted)
            TextEditor(text: $text)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textNormal)
                .scrollContentBackground(.hidden)
                // Inset matches the gap AppKit leaves between a text view's edge and its
                // first glyph, so the placeholder sits exactly where the caret does.
                .placeholder(
                    placeholder, isVisible: text.isEmpty, alignment: .topLeading,
                    inset: Theme.Spacing.xs
                )
                .padding(Theme.Spacing.small)
                .frame(height: 80)
                .background(Theme.bgPrimary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.medium)
                        .stroke(Theme.border, lineWidth: Theme.hairline)
                )
        }
    }
}
