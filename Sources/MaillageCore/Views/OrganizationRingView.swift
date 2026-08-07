import AppKit
import SwiftUI

/// One organization's people on a circle, grouped into arcs by what they work on, with their
/// relations bundled through the middle.
///
/// The question a selected company asks is "who's here, on what, and who talks to whom?" — and
/// the previous board of project cards could only answer the first two. Relations are the
/// thing that makes a company more than a list, so they're drawn.
///
/// Position carries the grouping and the centre carries the connections, which is the trade
/// hierarchical edge bundling makes: a ring wastes the middle of the pane on nothing, and
/// spending it on the edges buys a picture where "this link crosses a project boundary" is
/// visible as a curve diving inward instead of hugging the rim.
///
/// Only this org's people are on the ring, plus outsiders they're actually linked to — see
/// ``RingLayout`` for how the arcs are chosen.
struct OrganizationRingView: View {
    @Environment(VaultStore.self) private var store

    let organization: Organization
    @Binding var selection: EntityID?

    /// Who the pointer is over. Hovering dims everything unconnected to them, which is the
    /// only affordance that makes a bundle of curves readable one relation at a time.
    @State private var hovered: EntityID?

    var body: some View {
        VStack(spacing: 0) {
            CenterPaneHeader(
                title: organization.displayName,
                subtitle: subtitle,
                color: Theme.organizationColor)

            if employees.isEmpty {
                EmptyStateView(
                    icon: "circle.dashed",
                    title: "Nobody here yet",
                    message:
                        "Set \(organization.displayName) as someone's employer and they'll appear on this ring, grouped by the projects they're on."
                )
            } else {
                GeometryReader { geometry in
                    let layout = RingLayout(arcs: arcs, in: geometry.size)
                    ring(layout)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
    }

    // MARK: Drawing

    private func ring(_ layout: RingLayout) -> some View {
        let edges = self.edges(among: layout)

        return ZStack {
            // Arc labels and the rim behind them, drawn first so nothing overlaps a name.
            ForEach(layout.arcs) { arc in
                arcLabel(arc, in: layout)
            }

            Canvas { context, _ in
                draw(edges: edges, in: layout, context: &context)
            }
            .allowsHitTesting(false)

            ForEach(layout.nodes) { node in
                nodeView(node, isConnected: isConnected(node.id, edges: edges))
            }
        }
    }

    /// The bundle. Every relation with both ends on this ring, bowed toward the centre by an
    /// amount that says whether it stayed inside one group.
    private func draw(edges: [RingEdge], in layout: RingLayout, context: inout GraphicsContext) {
        for edge in edges {
            guard let from = layout.node(id: edge.from), let to = layout.node(id: edge.to)
            else { continue }

            let ends = trimmed(from: from, to: to)
            // A link inside one arc barely bends, so it reads as local; one that crosses arcs
            // is pulled most of the way to the centre. That difference *is* the information
            // the bundling adds.
            let tension: CGFloat = edge.crossesArc ? 0.78 : 0.3
            let path = bundledPath(
                from: ends.start, to: ends.end, pullTo: layout.center, tension: tension)

            let isLit = hovered == nil || hovered == edge.from || hovered == edge.to
            let opacity = isLit ? 0.8 : 0.08
            context.stroke(
                path,
                with: .color(Theme.accent.opacity(opacity)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

            // Relations are one-way, so which end declared it is information the picture has
            // to carry. The head is aimed along the curve's arrival, not the straight chord.
            let midpoint = CGPoint(
                x: (ends.start.x + ends.end.x) / 2, y: (ends.start.y + ends.end.y) / 2)
            let control = CGPoint(
                x: midpoint.x + (layout.center.x - midpoint.x) * tension,
                y: midpoint.y + (layout.center.y - midpoint.y) * tension)
            context.fill(
                arrowhead(at: ends.end, approaching: control),
                with: .color(Theme.accent.opacity(opacity)))
        }
    }

    private func nodeView(_ node: GraphNode, isConnected: Bool) -> some View {
        let isSelected = node.id == selection
        let isLit = hovered == nil || hovered == node.id || isConnected

        return Circle()
            .fill(node.isHollow ? Theme.bgPrimary : node.color)
            .overlay {
                Circle().strokeBorder(
                    isSelected ? Theme.textNormal : (node.isHollow ? node.color : Theme.bgPrimary),
                    lineWidth: isSelected ? 2.5 : 1.5)
            }
            .frame(width: node.radius * 2, height: node.radius * 2)
            .overlay(alignment: .top) {
                Text(node.label)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .fixedSize()
                    .offset(y: node.radius * 2 + 2)
                    .allowsHitTesting(false)
            }
            .opacity(isLit ? 1 : 0.25)
            // The drawn dot is 14pt across, which is less than a pointer can be asked to
            // land on, so the target is padded the way ``graphHitSlop`` describes.
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
            .onTapGesture { selection = node.id }
            .clickableCursor()
    }

    /// An arc's name, sitting outside the rim at the arc's middle.
    ///
    /// Outside rather than inside, because the inside is where the edge bundle goes.
    ///
    /// Down the sides of the ring the label is anchored by its *inner* edge rather than its
    /// centre. Centring it puts half the word back inside the gap, on top of the member name it
    /// was meant to clear — and a member's name is centred under their dot, so at three o'clock
    /// the two grow toward each other. Anchoring makes the label grow outward instead.
    ///
    /// Both the gap and the width come from ``RingLayout/labelRoom`` rather than being fixed,
    /// because the rim is only pushed in as far as the pane can afford. On a narrow pane a fixed
    /// 44pt gap would start the word past the edge; scaling it, and letting a long label
    /// truncate, keeps the group's name on screen and readable.
    private func arcLabel(_ arc: RingLayout.Arc, in layout: RingLayout) -> some View {
        let room = layout.labelRoom
        let inset = min(RingLayout.labelInset, room * 0.4)
        let point = CGPoint.onCircle(
            center: layout.center,
            radius: layout.radius + inset,
            angle: arc.midAngle)
        // Which way "outward" is, horizontally. Near the top and bottom there's no meaningful
        // side, so the label keeps centring on its point — and it has half the pane either way,
        // rather than only what's beyond the rim.
        let side: CGFloat = abs(sin(arc.midAngle)) > 0.25 ? (sin(arc.midAngle) > 0 ? 1 : -1) : 0
        let width =
            side == 0
            ? RingLayout.labelReserve : min(RingLayout.labelReserve, max(room - inset, 32))

        return Text(arc.label)
            .font(Theme.Font.sectionHeader)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textFaint)
            .lineLimit(1)
            .truncationMode(.tail)
            // A transparent frame, aligned so the text hugs `point` on its inner side — which
            // anchors an edge without having to measure the string.
            .frame(width: width, alignment: side > 0 ? .leading : (side < 0 ? .trailing : .center))
            .position(x: point.x + side * width / 2, y: point.y)
            .allowsHitTesting(false)
    }

    // MARK: Arcs

    /// The ring's groups, in the order they're drawn.
    ///
    /// Projects first in the store's stable order, then the three computed buckets. Each
    /// person appears in exactly one — a dot has to mean one person, so somebody on two
    /// projects gets their own group rather than being drawn twice or silently assigned to
    /// whichever project happened to be listed first.
    private var arcs: [(label: String, people: [Person], color: Color)] {
        let projects = store.projects(inOrganization: organization.id)
        let hue = Theme.clusterColor(at: employerIndex)
        var result: [(label: String, people: [Person], color: Color)] = []

        // How many of *this org's* projects each employee is on. Projects elsewhere don't
        // count: this ring is about what the company works on.
        let projectIDs = Set(projects.map(\.id))
        var counts: [EntityID: Int] = [:]
        for person in employees {
            counts[person.id] = person.projects.filter { projectIDs.contains($0.to.id) }.count
        }

        for project in projects {
            let people = employees.filter {
                counts[$0.id] == 1 && $0.projects.contains { $0.to.id == project.id }
            }
            if !people.isEmpty {
                result.append((project.displayName, people, hue))
            }
        }

        let onSeveral = employees.filter { (counts[$0.id] ?? 0) > 1 }
        if !onSeveral.isEmpty {
            result.append(("On several", onSeveral, hue))
        }

        let onNone = employees.filter { (counts[$0.id] ?? 0) == 0 }
        if !onNone.isEmpty {
            result.append(("On no project", onNone, hue))
        }

        // Outsiders last, and only if they exist — a self-contained company shows no extra
        // arc. Tinted by their own employer, so it's visible that they belong elsewhere.
        if !outsiders.isEmpty {
            // One arc, but the colour varies per person, so it's split into single-person
            // entries sharing a label. `RingLayout` merges consecutive same-label arcs.
            for person in outsiders {
                result.append(("Outside", [person], colour(of: person)))
            }
        }
        return result
    }

    // MARK: Data

    private var employees: [Person] {
        store.members(ofOrganization: organization.id)
    }

    /// People elsewhere that this company's people have a relation to or from.
    ///
    /// Included rather than dropped, because a cross-company relation is often the whole
    /// reason the company is interesting — hiding it would make the ring claim the company is
    /// self-contained when it isn't.
    private var outsiders: [Person] {
        let inside = Set(employees.map(\.id))
        var found: Set<EntityID> = []
        for person in employees {
            for relation in person.relations where !inside.contains(relation.to.id) {
                if store.snapshot.people[relation.to.id] != nil { found.insert(relation.to.id) }
            }
            for backlink in store.backlinks(for: person.id) where !inside.contains(backlink.from) {
                if store.snapshot.people[backlink.from] != nil { found.insert(backlink.from) }
            }
        }
        return found.compactMap { store.snapshot.people[$0] }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// This organization's index in the store's stable order, which is where its hue comes
    /// from — so the ring is tinted the same colour as the bubble you clicked to get here.
    private var employerIndex: Int? {
        store.peopleGroupedByOrganization()
            .firstIndex { $0.organization?.id == organization.id }
    }

    private func colour(of person: Person) -> Color {
        let groups = store.peopleGroupedByOrganization()
        let index = groups.firstIndex { $0.organization?.id == person.organization?.id }
        guard let index, groups[index].organization != nil else { return Theme.noClusterColor }
        return Theme.clusterColor(at: index)
    }

    private var subtitle: String {
        let projectCount = store.projects(inOrganization: organization.id).count
        let peopleCount = employees.count
        return
            "\(peopleCount) \(peopleCount == 1 ? "person" : "people") · \(projectCount) project\(projectCount == 1 ? "" : "s")"
    }

    // MARK: Edges

    /// Relations with both endpoints on this ring, taken from the source's stored relations
    /// so each is drawn once, pointing the way it was declared.
    private func edges(among layout: RingLayout) -> [RingEdge] {
        let onRing = Set(layout.nodes.map(\.id))
        var edges: [RingEdge] = []
        for id in onRing {
            guard let person = store.snapshot.people[id] else { continue }
            for relation in person.relations where onRing.contains(relation.to.id) {
                edges.append(
                    RingEdge(
                        from: id, to: relation.to.id,
                        crossesArc: layout.arcIndex(of: id) != layout.arcIndex(of: relation.to.id)))
            }
        }
        // Sorted so the draw order — and therefore which curve is on top — doesn't depend on
        // set iteration.
        return edges.sorted { ($0.from, $0.to) < ($1.from, $1.to) }
    }

    private func isConnected(_ id: EntityID, edges: [RingEdge]) -> Bool {
        guard let hovered else { return false }
        return edges.contains {
            ($0.from == hovered && $0.to == id) || ($0.to == hovered && $0.from == id)
        }
    }
}

/// A relation to draw, and whether it leaves the group it started in — which is what decides
/// how hard it bows toward the centre.
private struct RingEdge {
    let from: EntityID
    let to: EntityID
    let crossesArc: Bool
}

// MARK: - Ring layout

/// Places people on one circle, in labelled arcs, with gaps so the arcs read as groups.
///
/// Pure geometry over its input arcs — it doesn't know what a project is, only that it was
/// handed ordered groups of people. That keeps the "who belongs in which group" decision in
/// the view, where the store lives, and the "where does that put them" decision here, where
/// it can be tested without a vault.
struct RingLayout {
    /// How far outside the rim an arc's label sits — beyond where a person's name is drawn,
    /// so the group's name and a member's name never land on each other. Scaled down when
    /// ``labelRoom`` is too small to spend this much on a gap.
    static let labelInset: CGFloat = 44
    /// How much room an arc label is given to grow outward, down the sides of the ring, where
    /// it's anchored by its inner edge rather than centred. Long enough for the longest label
    /// the view produces ("ON NO PROJECT") at ``Theme/Font/sectionHeader``, and capped by
    /// ``labelRoom`` so a narrow pane truncates the word instead of running it off the edge.
    static let labelReserve: CGFloat = 130
    /// The dot for one person. Uniform: this ring says nothing about importance.
    static let nodeRadius: CGFloat = 7
    /// Room left either side of the rim, wider than it is tall.
    ///
    /// Names are horizontal text centred under a dot, so a person at three o'clock needs half
    /// their name's width plus the arc label beyond the rim, while one at twelve needs only a
    /// line's height. Sizing both axes off the smaller need is what pushed names off the pane.
    ///
    /// A ceiling rather than a promise — see ``ringRadius(in:horizontal:vertical:floor:)``, which
    /// caps each margin at a share of the pane so a narrow one doesn't collapse the rim.
    static let horizontalMargin: CGFloat = 150
    static let verticalMargin: CGFloat = 80
    /// Angular gap between two arcs, in radians. Wide enough that a gap can't be mistaken for
    /// the spacing between two people inside one arc.
    static let arcGap: CGFloat = 0.14

    /// One drawn group: which people, where it starts and ends, and what to call it.
    struct Arc: Identifiable {
        let id: Int
        let label: String
        let color: Color
        /// Radians, clockwise from straight up.
        let startAngle: CGFloat
        let endAngle: CGFloat
        let personIDs: [EntityID]

        var midAngle: CGFloat { (startAngle + endAngle) / 2 }
    }

    let center: CGPoint
    let radius: CGFloat
    let arcs: [Arc]
    let nodes: [GraphNode]
    /// How much pane there is between the rim and the edge, either side.
    ///
    /// The margin the rim was asked for is only a ceiling, so this is what an arc label actually
    /// has to fit its gap and its text into. Never negative: a rim at its floor on a tiny pane
    /// still leaves room, it's just small.
    let labelRoom: CGFloat
    private let arcIndices: [EntityID: Int]

    init(arcs input: [(label: String, people: [Person], color: Color)], in size: CGSize) {
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        radius = ringRadius(
            in: size, horizontal: Self.horizontalMargin, vertical: Self.verticalMargin,
            floor: Self.nodeRadius * 2)
        labelRoom = max(size.width / 2 - radius, 0)

        // Consecutive entries sharing a label are one arc — the view splits "Outside" into
        // one entry per person so each can carry its own employer's hue, and this puts them
        // back together so the label is drawn once over the whole run.
        var merged: [(label: String, people: [(Person, Color)])] = []
        for entry in input {
            let tinted = entry.people.map { ($0, entry.color) }
            if merged.last?.label == entry.label {
                merged[merged.count - 1].people.append(contentsOf: tinted)
            } else {
                merged.append((entry.label, tinted))
            }
        }

        let total = merged.reduce(0) { $0 + $1.people.count }
        guard total > 0 else {
            self.arcs = []
            nodes = []
            arcIndices = [:]
            return
        }

        // Arcs are sized by headcount so every person gets the same slice of the circle;
        // otherwise a one-person arc would space its dot as widely as a six-person arc packs
        // six, and the ring would misreport who is where.
        let gapTotal = merged.count > 1 ? Self.arcGap * CGFloat(merged.count) : 0
        let usable = max(2 * CGFloat.pi - gapTotal, 0.1)

        var builtArcs: [Arc] = []
        var builtNodes: [GraphNode] = []
        var indices: [EntityID: Int] = [:]
        var angle: CGFloat = merged.count > 1 ? Self.arcGap / 2 : 0

        for (index, group) in merged.enumerated() {
            let extent = usable * CGFloat(group.people.count) / CGFloat(total)
            let start = angle
            let end = angle + extent

            for (slot, entry) in group.people.enumerated() {
                let (person, colour) = entry
                // Spaced at slot centres rather than endpoints, so a lone person sits at the
                // arc's middle — under its label — instead of on the boundary with the next.
                let fraction = (CGFloat(slot) + 0.5) / CGFloat(group.people.count)
                let nodeAngle = start + extent * fraction
                builtNodes.append(
                    GraphNode(
                        id: person.id,
                        center: .onCircle(center: center, radius: radius, angle: nodeAngle),
                        radius: Self.nodeRadius,
                        color: colour,
                        label: person.displayName,
                        isHollow: person.placeholder))
                indices[person.id] = index
            }

            builtArcs.append(
                Arc(
                    id: index,
                    label: group.label,
                    color: group.people.first?.1 ?? Theme.noClusterColor,
                    startAngle: start,
                    endAngle: end,
                    personIDs: group.people.map(\.0.id)))
            angle = end + Self.arcGap
        }

        self.arcs = builtArcs
        nodes = builtNodes
        arcIndices = indices
    }

    // MARK: Lookups

    func node(id: EntityID) -> GraphNode? {
        nodes.first { $0.id == id }
    }

    /// Which arc a person was placed in, or `nil` if they're not on this ring.
    func arcIndex(of id: EntityID) -> Int? {
        arcIndices[id]
    }
}
