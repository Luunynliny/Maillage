import SwiftUI

/// The circle that stands for one entity: its logo if it has one, otherwise its kind's glyph.
///
/// One component for every such circle in the app, so a logo cannot appear as a photo in the
/// sidebar and a coloured dot in the palette — that inconsistency is the reason the old
/// per-site `Circle().fill(…)` calls were replaced rather than supplemented.
///
/// The fallback keeps the kind's hue, so the colour coding that used to be the *whole* signal
/// survives as the default: a vault with no logos still reads purple-for-people at a glance.
/// What the hue can no longer do is say *which* person — that's the logo's job.
public struct EntityAvatar: View {
    /// How the circle is filled when there is no logo to show.
    public enum Fill {
        /// Glyph in the tint over a wash of it. For rows, headers and cards, where the circle
        /// sits beside text and a saturated disc would shout over the name it belongs to.
        case wash
        /// Glyph knocked out of a saturated disc of the tint. For the graphs, where the hue
        /// *is* the information — it says which employer — and a 15% wash would not carry it
        /// across a pane.
        case solid
    }

    /// Optional, so an avatar in a preview or outside the app's environment falls back to its
    /// glyph rather than trapping on a missing store.
    @Environment(VaultStore.self) private var store: VaultStore?

    private let kind: EntityKind
    private let id: EntityID
    private let size: CGFloat
    private let isPlaceholder: Bool
    private let tint: Color?
    private let fill: Fill
    private let ring: Color?

    /// `tint` overrides the kind's hue — the graphs pass an employer colour, where a hue means
    /// "which company" rather than "which kind". `ring` outlines the circle in that same colour,
    /// which is how a logo in the ego graph still says who someone works for: the hue there is
    /// also the ring's sort order, so it can't simply be dropped in favour of the image.
    public init(
        kind: EntityKind,
        id: EntityID,
        size: CGFloat = Theme.Avatar.row,
        isPlaceholder: Bool = false,
        tint: Color? = nil,
        fill: Fill = .wash,
        ring: Color? = nil
    ) {
        self.kind = kind
        self.id = id
        self.size = size
        self.isPlaceholder = isPlaceholder
        self.tint = tint
        self.fill = fill
        self.ring = ring
    }

    public var body: some View {
        content
            .frame(width: size, height: size)
            .overlay {
                if let ring {
                    Circle().strokeBorder(ring, lineWidth: max(1, size / 14))
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let logo = store?.logo(kind: kind, id: id) {
            Image(nsImage: logo)
                .resizable()
                // Already a centre-cropped square from ``ImageSquarer``, so this only guards
                // against a hand-placed PNG that isn't square.
                .aspectRatio(contentMode: .fill)
                .clipShape(Circle())
        } else if isPlaceholder {
            // Hollow, as the sidebar's dot was: a person with no name has nothing to show, and
            // an outline reads as "not yet known" without needing a colour of its own.
            Circle()
                .strokeBorder(colour, lineWidth: max(1.5, size / 13))
                .overlay { glyph(in: colour).opacity(0.55) }
        } else {
            switch fill {
            case .wash:
                Circle()
                    .fill(colour.opacity(0.15))
                    .overlay { glyph(in: colour) }
            case .solid:
                Circle()
                    .fill(colour)
                    .overlay { glyph(in: Theme.bgPrimary) }
            }
        }
    }

    /// Sized as a fraction of the circle rather than from ``Theme/Font``, so one glyph sits the
    /// same way inside a 16pt board marker and a 64pt editor well.
    private func glyph(in color: Color) -> some View {
        Image(systemName: kind.symbolName)
            .font(.system(size: size * 0.46))
            .foregroundStyle(color)
    }

    /// Placeholders desaturate on their own, so a caller doesn't have to remember to pass
    /// ``Theme/placeholderColor`` alongside the flag it already passed — the two always agreed
    /// at the old dot's call sites anyway.
    private var colour: Color {
        if let tint { return tint }
        return isPlaceholder ? Theme.placeholderColor : Theme.color(for: kind)
    }
}
