import SwiftUI

/// The whole network at a glance: one circle per employer, sized by headcount, with the
/// count written inside it.
///
/// This is what the centre pane shows before you've selected anything, and the question it
/// answers is "what does my network look like?" — which is a question about *companies*, not
/// about individuals. Drawing all fifteen people and every relation between them here made a
/// hairball you could not read a headcount off of, and person↔person edges are noise until
/// you've asked about a person.
///
/// Area tracks headcount rather than radius, so a five-person company looks like more than a
/// two-person one by the amount it actually is. Clicking a bubble selects the organization,
/// which switches the pane to ``OrganizationBoardView`` — the bubbles are the entry point to
/// the other views, not a dead end.
struct OrganizationBubblesView: View {
    @Environment(VaultStore.self) private var store
    @Binding var selection: EntityID?

    /// Which bubble the pointer is over, so hover can raise its wash. Tracked here rather
    /// than per-bubble so leaving one and entering another can't leave two lit.
    @State private var hovered: EntityID?

    var body: some View {
        if store.allPeople.isEmpty {
            EmptyStateView(
                icon: "circle.grid.2x2",
                title: "Nothing to show yet",
                message:
                    "Add a few people and the companies they work for, and each one will appear here sized by how many people you know there."
            )
        } else {
            GeometryReader { geometry in
                let packing = BubblePacking(
                    groups: store.peopleGroupedByOrganization(), in: geometry.size)

                ZStack {
                    ForEach(packing.bubbles) { bubble in
                        bubbleView(bubble)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    private func bubbleView(_ bubble: BubblePacking.Bubble) -> some View {
        let isHovered = bubble.id != nil && bubble.id == hovered
        let diameter = bubble.radius * 2

        return Circle()
            .fill(bubble.color.opacity(isHovered ? 0.26 : 0.14))
            .overlay {
                Circle().strokeBorder(
                    bubble.color.opacity(isHovered ? 0.95 : 0.5),
                    lineWidth: isHovered ? 2 : Theme.hairline)
            }
            .overlay {
                label(bubble)
            }
            .frame(width: diameter, height: diameter)
            // Without this the square frame swallows clicks aimed at the gap between two
            // bubbles, and the hand cursor appears well outside the drawn circle.
            .contentShape(Circle())
            // Everything interactive goes on *before* `.position`, which is not cosmetic
            // ordering. `.position` returns a view that fills the whole pane and draws its
            // child at one point inside it — so a hover or tap attached after it is attached
            // to the entire graph area, not to the circle. Every bubble then claimed the same
            // full-pane region, the last one in the `ZStack` won, and since that one is the
            // unaffiliated bucket the result was no hand and no hover wash anywhere on the
            // view.
            .onHover { inside in
                guard let id = bubble.id else { return }
                if inside {
                    hovered = id
                } else if hovered == id {
                    hovered = nil
                }
            }
            .onTapGesture {
                if let id = bubble.id { selection = id }
            }
            // The grey bucket has no organization behind it, so nothing to select — and a
            // hand there would promise a click that does nothing.
            .clickableCursor(bubble.id != nil)
            .position(bubble.center)
    }

    /// The count is the payload, so it gets the largest type and the centre; the name is what
    /// tells you which company it belongs to.
    ///
    /// Both shrink rather than clip, because the packing is scaled to fit the pane and a
    /// narrow pane leaves small bubbles — a number that overflows its circle would be worse
    /// than a smaller one.
    private func label(_ bubble: BubblePacking.Bubble) -> some View {
        VStack(spacing: 0) {
            Text("\(bubble.headcount)")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.textNormal)
            Text(bubble.name)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .minimumScaleFactor(0.5)
        // A square inscribed in the circle, so a long company name wraps instead of
        // spilling past the rim.
        .frame(width: bubble.radius * 1.4)
        .allowsHitTesting(false)
    }
}

// MARK: - Packing

/// Places one circle per employer so that none overlap and the whole arrangement fills the
/// pane it's given.
///
/// Pure geometry, and deterministic: same groups and same size in, same circles out. That's
/// what makes "Acme is the big one in the middle" stay true between launches, and it's why
/// this is a struct the tests can drive without a window.
struct BubblePacking {
    /// Radius for a company you know one person at. Below this a circle stops being able to
    /// hold a two-digit number and a name.
    static let minRadius: CGFloat = 44
    /// Ceiling, so one large employer can't swallow the pane before scaling even starts.
    static let maxRadius: CGFloat = 150
    /// Clear space guaranteed between two circles' rims, before scaling.
    static let gap: CGFloat = 12
    /// How much bigger the packing may be drawn than its natural size. Without a ceiling, a
    /// vault with one company would blow that single circle up to fill the window.
    static let maxUpscale: CGFloat = 1.35

    struct Bubble: Identifiable {
        /// The organization's id, or `nil` for the "no employer" bucket — which is also what
        /// makes that one unclickable, since there's no entity to select.
        let id: EntityID?
        let name: String
        let center: CGPoint
        let radius: CGFloat
        let color: Color
        let headcount: Int
    }

    let bubbles: [Bubble]

    init(groups: [(organization: Organization?, people: [Person])], in size: CGSize) {
        // Hue comes from the group's position in the store's order, not from the packing's,
        // so a company keeps its colour whether or not it happens to be the biggest.
        let coloured = groups.enumerated().map { index, group in
            (
                id: group.organization?.id,
                name: group.organization?.displayName ?? "No employer",
                headcount: group.people.count,
                color: Theme.clusterColor(at: group.organization == nil ? nil : index)
            )
        }

        // Biggest first: it takes the centre, and every later circle packs around what's
        // already there. Ties break on name so the order can't depend on dictionary
        // iteration. The unaffiliated bucket sorts last whatever its size — "no employer"
        // isn't a company, so it shouldn't be presented as the largest one.
        let ordered = coloured.sorted {
            if ($0.id == nil) != ($1.id == nil) { return $1.id == nil }
            if $0.headcount != $1.headcount { return $0.headcount > $1.headcount }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        var placed: [(center: CGPoint, radius: CGFloat)] = []
        for group in ordered {
            let radius = Self.radius(headcount: group.headcount)
            placed.append((Self.position(radius: radius, among: placed), radius))
        }

        let fit = Self.fit(placed, in: size)
        bubbles = zip(ordered, placed).map { group, circle in
            Bubble(
                id: group.id,
                name: group.name,
                center: CGPoint(
                    x: circle.center.x * fit.scale + fit.offset.x,
                    y: circle.center.y * fit.scale + fit.offset.y),
                radius: circle.radius * fit.scale,
                color: group.color,
                headcount: group.headcount)
        }
    }

    // MARK: Geometry

    /// Grows on a square root, so *area* tracks headcount: doubling the radius would claim
    /// four times the people.
    static func radius(headcount: Int) -> CGFloat {
        let grown = minRadius + 26 * CGFloat(max(headcount, 1) - 1).squareRoot()
        return min(grown, maxRadius)
    }

    /// The nearest spot to the centre where a circle of `radius` clears everything already
    /// placed.
    ///
    /// A spiral sweep — step outward, and at each distance try every angle — rather than
    /// anything cleverer. With a handful of employers it lands on a tight cluster, and being
    /// exhaustive in a fixed order is what makes it reproducible: no seeds, no relaxation
    /// passes, no dependence on which circle was considered first.
    static func position(radius: CGFloat, among placed: [(center: CGPoint, radius: CGFloat)])
        -> CGPoint
    {
        guard !placed.isEmpty else { return .zero }

        let step: CGFloat = 3
        let angleCount = 90
        // Nothing can clear the centre circle closer in than this, so start there instead of
        // sweeping distances that cannot possibly work.
        var distance = (placed.first?.radius ?? 0) + radius + gap
        // Every circle in a line is the loosest packing possible, so no valid spot can be
        // further out than that.
        let limit = placed.reduce(radius) { $0 + $1.radius * 2 + gap } + gap

        while distance <= limit {
            for index in 0..<angleCount {
                let angle = 2 * CGFloat.pi * CGFloat(index) / CGFloat(angleCount)
                let candidate = CGPoint.onCircle(center: .zero, radius: distance, angle: angle)
                let clears = placed.allSatisfy {
                    candidate.distance(to: $0.center) >= radius + $0.radius + gap
                }
                if clears { return candidate }
            }
            distance += step
        }
        // Unreachable with the limit above, but a definite answer beats a crash.
        return CGPoint(x: limit, y: 0)
    }

    /// How to move and scale the packing so it sits centred in `size` and fills it.
    ///
    /// Scaling is what makes one layout work in a 400pt pane and a 1400pt one, and it's the
    /// reason the packing above can be computed in its own units without knowing the window.
    static func fit(_ placed: [(center: CGPoint, radius: CGFloat)], in size: CGSize)
        -> (scale: CGFloat, offset: CGPoint)
    {
        let padding = Theme.Spacing.xl
        let available = CGSize(
            width: max(size.width - padding * 2, 1),
            height: max(size.height - padding * 2, 1))

        guard !placed.isEmpty else { return (1, CGPoint(x: size.width / 2, y: size.height / 2)) }

        let minX = placed.map { $0.center.x - $0.radius }.min() ?? 0
        let maxX = placed.map { $0.center.x + $0.radius }.max() ?? 0
        let minY = placed.map { $0.center.y - $0.radius }.min() ?? 0
        let maxY = placed.map { $0.center.y + $0.radius }.max() ?? 0
        let width = max(maxX - minX, 1)
        let height = max(maxY - minY, 1)

        let scale = min(available.width / width, available.height / height, maxUpscale)
        // Centre the packing's own bounding box, not its origin: the largest circle sits at
        // the origin, and everything else grew off to one side of it.
        let centre = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        return (
            scale,
            CGPoint(
                x: size.width / 2 - centre.x * scale,
                y: size.height / 2 - centre.y * scale)
        )
    }

    // MARK: Lookups

    /// The bubble containing `point`, smallest first so a circle nested inside another wins.
    ///
    /// Not used for hit-testing — SwiftUI's own `contentShape(Circle())` does that — but the
    /// tests assert against it, and it's the one place that states what "inside a bubble"
    /// means.
    func bubble(at point: CGPoint) -> Bubble? {
        bubbles
            .filter { point.distance(to: $0.center) <= $0.radius }
            .min { $0.radius < $1.radius }
    }
}
