import SwiftUI

/// Small uppercase label that groups sidebar and detail sections, with an optional count.
///
/// Sizes to its content rather than filling the width it's given, so the count sits beside the
/// word it counts. It used to hold a `Spacer`, which pushed the count to the far right of
/// whatever container it landed in — across a full-width details pane that left "REFERENCED BY"
/// and its "2" at opposite ends of the window, reading as two unrelated things. A caller that
/// genuinely wants the label to span adds its own `Spacer`; the sidebar is the one that does.
public struct SectionHeader: View {
    private let title: String
    private let trailing: String?

    public init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            Text(title.uppercased())
                .font(Theme.Font.sectionHeader)
                .tracking(0.6)
                .foregroundStyle(Theme.textFaint)
            if let trailing {
                Text(trailing)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textFaint)
            }
        }
    }
}

/// The triangle that says whether a collapsible section is open.
///
/// One glyph rotated rather than two symbols swapped, so the arrow is visibly the *same*
/// arrow in both states instead of two that happen to sit in the same place.
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
            // Snaps rather than spins. `rotationEffect` is animatable, so an animation
            // anywhere up the tree would otherwise pick it up and turn the glyph — and the
            // rows it describes appear instantly, so a turning arrow would lag them.
            .animation(nil, value: isExpanded)
            // Fixed square: rotating a non-square glyph changes the width it claims, which
            // would shove the section title sideways on every toggle.
            .frame(width: Theme.chevron, height: Theme.chevron)
    }
}
