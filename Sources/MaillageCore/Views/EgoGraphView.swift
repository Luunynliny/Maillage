import SwiftUI

/// One person at the centre and everyone they're directly linked to around them.
///
/// The question a selected person asks is "who does this person actually know?", and the
/// honest answer is one hop. Two hops looks like more information but isn't: the second ring
/// is other people's networks, and the labels — which are the point, since a relation means
/// nothing without `manager of` on it — stop fitting.
///
/// Both directions are shown. Relations are one-way on disk, so a person you declared and a
/// person who declared you are different facts; each spoke's arrowhead says which. Neighbours
/// are tinted and grouped by employer, so colleagues sit together — the same hue means the
/// same company here as in ``OrganizationBubblesView``.
struct EgoGraphView: View {
    @Environment(VaultStore.self) private var store

    let person: Person
    @Binding var selection: EntityID?
    /// So the empty state and the header can offer the editors that fill and change them.
    @Binding var editorRequest: EditorRequest?
    /// Whether the header's details section is folded out. Owned by ``RootView``.
    @Binding var isDetailVisible: Bool

    @State private var hovered: EntityID?

    var body: some View {
        VStack(spacing: 0) {
            CenterPaneHeader(
                entity: .person(person),
                subtitle: subtitle,
                isDetailVisible: $isDetailVisible,
                selection: $selection,
                editorRequest: $editorRequest)

            if spokes.isEmpty {
                EmptyStateView(
                    icon: "point.topleft.down.to.point.bottomright.curvepath",
                    title: "No relations yet",
                    message:
                        "Link \(person.displayName) to someone and this becomes a map of who they know.",
                    actionTitle: "Add a relation…",
                    action: { editorRequest = .addRelation(person.id) }
                )
            } else {
                GeometryReader { geometry in
                    let layout = EgoLayout(
                        subject: person, neighbours: neighbours, spokes: spokes,
                        in: geometry.size, employer: employerIndex(of:))
                    graph(layout)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
    }

    // MARK: Drawing

    private func graph(_ layout: EgoLayout) -> some View {
        ZStack {
            Canvas { context, _ in
                draw(layout, context: &context)
            }
            .allowsHitTesting(false)

            ForEach(layout.labels) { label in
                spokeLabel(label)
            }

            ForEach(layout.nodes) { node in
                nodeView(node, isSubject: node.id == person.id)
            }
        }
    }

    /// One line per relation, so a mutual pair draws two.
    ///
    /// Bowed to opposite sides rather than overlaid, because two arrows on one straight line
    /// would sit head-to-tail and read as a single ambiguous link — and the pair *is* the
    /// interesting case.
    private func draw(_ layout: EgoLayout, context: inout GraphicsContext) {
        for spoke in layout.spokes {
            guard let subject = layout.node(id: person.id),
                let neighbour = layout.node(id: spoke.neighbour)
            else { continue }

            let isLit = hovered == nil || hovered == spoke.neighbour
            let opacity = isLit ? 0.8 : 0.12
            let (from, to) =
                spoke.isOutbound ? (subject, neighbour) : (neighbour, subject)
            let ends = trimmed(from: from, to: to)
            let control = layout.control(for: spoke, from: ends.start, to: ends.end)

            context.stroke(
                Path { path in
                    path.move(to: ends.start)
                    path.addQuadCurve(to: ends.end, control: control)
                },
                with: .color(Theme.accent.opacity(opacity)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            context.fill(
                arrowhead(at: ends.end, approaching: control),
                with: .color(Theme.accent.opacity(opacity)))
        }
    }

    private func nodeView(_ node: GraphNode, isSubject: Bool) -> some View {
        let isLit = hovered == nil || hovered == node.id || isSubject

        return Circle()
            .fill(node.isHollow ? Theme.bgPrimary : node.color)
            .overlay {
                Circle().strokeBorder(
                    isSubject ? Theme.textNormal : (node.isHollow ? node.color : Theme.bgPrimary),
                    lineWidth: isSubject ? 2.5 : 1.5)
            }
            .frame(width: node.radius * 2, height: node.radius * 2)
            .overlay(alignment: .top) {
                Text(node.label)
                    .font(isSubject ? Theme.Font.heading : Theme.Font.caption)
                    .foregroundStyle(isSubject ? Theme.textNormal : Theme.textMuted)
                    .lineLimit(1)
                    .fixedSize()
                    .offset(y: node.radius * 2 + 2)
                    .allowsHitTesting(false)
            }
            .opacity(isLit ? 1 : 0.3)
            .contentShape(Circle().size(
                width: node.radius * 2 + graphHitSlop * 2,
                height: node.radius * 2 + graphHitSlop * 2
            ).offset(x: -graphHitSlop, y: -graphHitSlop))
            .position(node.center)
            .onHover { inside in
                if inside {
                    hovered = node.id
                } else if hovered == node.id {
                    hovered = nil
                }
            }
            // Clicking a neighbour re-centres on them, which is what makes the view walkable
            // rather than a single snapshot. The subject is already selected, so it's inert.
            .onTapGesture { selection = node.id }
            .clickableCursor(!isSubject)
    }

    /// The relation's own words, at the curve's midpoint.
    ///
    /// A relation with no label is just "these two are connected", which the line already
    /// said — so the label is the payload and gets a chip of background to stay readable
    /// where it crosses another spoke.
    private func spokeLabel(_ label: EgoLayout.SpokeLabel) -> some View {
        Text(label.text)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.textMuted)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, 1)
            .background(Theme.bgPrimary.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small))
            .opacity(hovered == nil || hovered == label.neighbour ? 1 : 0.12)
            .position(label.point)
            .allowsHitTesting(false)
    }

    // MARK: Data

    /// Every relation touching this person, in either direction, dangling targets skipped.
    ///
    /// Outbound comes from their own file; inbound from ``VaultStore/backlinks(for:)``, which
    /// is the in-memory inverse of everyone else's — the one-way-on-disk rule means the two
    /// halves are read from different places.
    private var spokes: [EgoSpoke] {
        var result: [EgoSpoke] = []
        for relation in person.relations
        where store.snapshot.people[relation.to.id] != nil && relation.to.id != person.id {
            result.append(
                EgoSpoke(neighbour: relation.to.id, label: relation.label, isOutbound: true))
        }
        for backlink in store.backlinks(for: person.id)
        where store.snapshot.people[backlink.from] != nil && backlink.from != person.id {
            result.append(
                EgoSpoke(neighbour: backlink.from, label: backlink.label, isOutbound: false))
        }
        return result
    }

    /// The people the spokes point at, so the layout can name them without reaching back into
    /// the store.
    private var neighbours: [EntityID: Person] {
        var result: [EntityID: Person] = [:]
        for spoke in spokes {
            result[spoke.neighbour] = store.snapshot.people[spoke.neighbour]
        }
        return result
    }

    /// A person's employer as its index in the store's stable organization order — the same
    /// number ``Theme/clusterColor(at:)`` takes, so a colleague here is the same hue as in the
    /// bubbles.
    private func employerIndex(of id: EntityID) -> Int? {
        guard let employer = store.snapshot.people[id]?.organization?.id else { return nil }
        let groups = store.peopleGroupedByOrganization()
        guard let index = groups.firstIndex(where: { $0.organization?.id == employer })
        else { return nil }
        return index
    }

    private var subtitle: String {
        let neighbours = Set(spokes.map(\.neighbour)).count
        let count = spokes.count
        return
            "\(count) relation\(count == 1 ? "" : "s") · \(neighbours) \(neighbours == 1 ? "person" : "people")"
    }
}

/// One relation seen from the subject's side: who's on the other end, what it's called, and
/// whether the subject declared it or someone declared them.
struct EgoSpoke: Hashable {
    let neighbour: EntityID
    let label: String
    let isOutbound: Bool
}

// MARK: - Ego layout

/// Subject at the centre, neighbours on one ring around them.
///
/// Pure geometry given the spokes and a way to look up an employer's hue. Deduplicating
/// neighbours is part of the layout rather than the view's job, because it's the invariant
/// that matters here: one dot must mean one person, however many relations reach them.
struct EgoLayout {
    static let subjectRadius: CGFloat = 11
    static let neighbourRadius: CGFloat = 7
    /// Room left either side of the ring. Wider than it is tall because a name is horizontal
    /// text: a neighbour at three o'clock needs half their name's width clear of the rim, not
    /// a line's height.
    ///
    /// Capped at a share of the pane by ``ringRadius(in:horizontal:vertical:floor:)``, so a
    /// narrow pane spreads the neighbours out rather than collapsing them onto the subject.
    static let horizontalMargin: CGFloat = 130
    static let verticalMargin: CGFloat = 70
    /// How far apart two edges between the same pair bow, so a mutual pair reads as two.
    static let pairSpread: CGFloat = 0.16

    /// A relation's label, already positioned.
    struct SpokeLabel: Identifiable {
        let id: String
        let text: String
        let point: CGPoint
        let neighbour: EntityID
    }

    let center: CGPoint
    let radius: CGFloat
    let nodes: [GraphNode]
    let spokes: [EgoSpoke]
    let labels: [SpokeLabel]
    /// Per spoke, how far its curve bows and to which side. Keyed the way `spokes` is ordered.
    private let bows: [CGFloat]

    /// `neighbours` supplies the people the spokes point at, and `employer` their position in
    /// the store's organization order (`nil` for nobody's employee).
    ///
    /// Both are passed in rather than looked up, so this stays a value type the tests can
    /// build without a vault. `employer` decides the hue *and* the ring order from one number,
    /// which is what guarantees colleagues both share a colour and sit next to each other —
    /// two closures could disagree.
    init(
        subject: Person, neighbours: [EntityID: Person], spokes: [EgoSpoke], in size: CGSize,
        employer: (EntityID) -> Int?
    ) {
        // Locals first, so the rest of the initializer can read them — a stored property can't
        // be read before every one of them is set.
        let origin = CGPoint(x: size.width / 2, y: size.height / 2)
        let ringRadius = MaillageCore.ringRadius(
            in: size, horizontal: Self.horizontalMargin, vertical: Self.verticalMargin,
            floor: Self.subjectRadius * 3)
        center = origin
        radius = ringRadius

        // One entry per neighbour, however many relations reach them — one dot means one
        // person. Ordered by employer then name, so colleagues sit together and the ring comes
        // out the same on every launch. No employer sorts last, like the store's own bucket.
        let unique = Set(spokes.map(\.neighbour))
        let ordered = unique.sorted { left, right in
            let leftRank = employer(left) ?? Int.max
            let rightRank = employer(right) ?? Int.max
            if leftRank != rightRank { return leftRank < rightRank }
            let leftName = neighbours[left]?.displayName ?? left
            let rightName = neighbours[right]?.displayName ?? right
            if leftName != rightName {
                return leftName.localizedStandardCompare(rightName) == .orderedAscending
            }
            return left < right
        }
        self.spokes = spokes

        var built: [GraphNode] = [
            GraphNode(
                id: subject.id,
                center: origin,
                radius: Self.subjectRadius,
                color: Theme.clusterColor(at: employer(subject.id)),
                label: subject.displayName,
                isHollow: subject.placeholder)
        ]

        for (index, id) in ordered.enumerated() {
            let angle = 2 * CGFloat.pi * CGFloat(index) / CGFloat(ordered.count)
            built.append(
                GraphNode(
                    id: id,
                    center: .onCircle(center: origin, radius: ringRadius, angle: angle),
                    radius: Self.neighbourRadius,
                    color: Theme.clusterColor(at: employer(id)),
                    label: neighbours[id]?.displayName ?? id,
                    isHollow: neighbours[id]?.placeholder ?? false))
        }
        nodes = built

        // A pair with relations both ways gets its two curves bowed to opposite sides; a lone
        // relation stays straight, since there's nothing to disambiguate it from.
        var perNeighbour: [EntityID: Int] = [:]
        var bows: [CGFloat] = []
        for spoke in spokes {
            let ordinal = perNeighbour[spoke.neighbour, default: 0]
            perNeighbour[spoke.neighbour] = ordinal + 1
            let count = spokes.filter { $0.neighbour == spoke.neighbour }.count
            bows.append(
                count > 1
                    ? Self.pairSpread * (CGFloat(ordinal) - CGFloat(count - 1) / 2) * 2
                    : 0)
        }
        self.bows = bows

        var builtLabels: [SpokeLabel] = []
        for (index, spoke) in spokes.enumerated() {
            let neighbourCentre = built.first { $0.id == spoke.neighbour }?.center ?? origin
            let midpoint = CGPoint(
                x: (origin.x + neighbourCentre.x) / 2, y: (origin.y + neighbourCentre.y) / 2)
            // Offset perpendicular to the spoke by half what the curve bows, so a label sits
            // on its own line rather than between two.
            let dx = neighbourCentre.x - origin.x
            let dy = neighbourCentre.y - origin.y
            let length = max((dx * dx + dy * dy).squareRoot(), 1)
            let offset = bows[index] * length / 2
            builtLabels.append(
                SpokeLabel(
                    id: "\(spoke.neighbour)|\(spoke.label)|\(spoke.isOutbound)",
                    text: spoke.label,
                    point: CGPoint(
                        x: midpoint.x - dy / length * offset,
                        y: midpoint.y + dx / length * offset),
                    neighbour: spoke.neighbour))
        }
        labels = builtLabels
    }

    // MARK: Lookups

    func node(id: EntityID) -> GraphNode? {
        nodes.first { $0.id == id }
    }

    /// The quadratic control point for a spoke's curve — off the straight line by however far
    /// this spoke was told to bow.
    func control(for spoke: EgoSpoke, from: CGPoint, to: CGPoint) -> CGPoint {
        guard let index = spokes.firstIndex(of: spoke) else {
            return CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        }
        let midpoint = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = max((dx * dx + dy * dy).squareRoot(), 1)
        let offset = bows[index] * length
        return CGPoint(x: midpoint.x - dy / length * offset, y: midpoint.y + dx / length * offset)
    }
}
