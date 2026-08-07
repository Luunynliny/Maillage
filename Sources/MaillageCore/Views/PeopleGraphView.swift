import AppKit
import Grape
import SwiftUI

/// Everyone in the vault as a network, grouped into one bubble per employer.
///
/// Nodes are people — projects belong to the other two centre-pane views, and dropping them
/// is what turns a hairball back into something readable. The one kind of edge drawn is a
/// person → person **relation**, with an arrowhead because it is one-way; membership needs no
/// edge, because it's expressed by which bubble someone sits in.
///
/// Clustering is done by pinning each group to a point on a ring and pulling its members
/// toward it, rather than by letting repulsion sort things out. Springs alone don't
/// separate groups — they interleave, and the result differs on every launch. Anchors are
/// derived from the group's *index*, so the same vault lays out the same way every time
/// and the picture becomes memorable.
///
/// The grouping is then *drawn* rather than implied, two ways that reinforce each other: a
/// tinted bubble names each company and bounds it, and every dot carries its employer's hue,
/// so a person stays legible mid-drag or sitting on a bubble's edge. Organizations are
/// therefore no longer nodes; a circle at the centre would compete with the bubble labelling
/// it, and the bubble carries both the name and the headcount.
struct PeopleGraphView: View {
    @Environment(VaultStore.self) private var store
    @Binding var selection: EntityID?

    // A perpetually running simulation re-renders at 60 fps and starves text input
    // everywhere in the app, so settle the layout once on appear and stay idle.
    @State private var graphState = ForceDirectedGraphState(
        initialIsRunning: false,
        ticksOnAppear: .untilStable)

    /// Whether the pointer is currently over something clickable, so the hand cursor is
    /// pushed and popped exactly once per crossing instead of on every hover sample.
    @State private var isHoveringTarget = false

    var body: some View {
        ZStack {
            Theme.bgPrimary.ignoresSafeArea()

            if store.allPeople.isEmpty {
                EmptyStateView(
                    icon: "point.3.filled.connected.trianglepath.dotted",
                    title: "Nothing to graph yet",
                    message:
                        "Add a few people and the relations between them and they'll appear here as a network."
                )
            } else {
                graph
                legend
            }
        }
    }

    /// One layout per render, shared by the nodes, their tint, the bubbles and hit-testing —
    /// they must agree on every anchor, so they cannot each build their own.
    private var layout: ClusterLayout {
        ClusterLayout(groups: store.peopleGroupedByOrganization())
    }

    // MARK: Graph

    private var graph: some View {
        // Recomputing the node/edge lists once per render keeps the GraphContent
        // builder cheap and avoids repeated dictionary lookups inside it.
        let layout = self.layout
        let nodes = layout.nodes
        let relationEdges = self.relationEdges

        return ForceDirectedGraph(states: graphState) {
            Series(nodes) { person in
                let hue = Theme.clusterColor(at: layout.groupIndex(for: person.id))
                let isSelected = person.id == selection
                NodeMark(id: person.id)
                    .symbolSize(radius: Self.personRadius)
                    // The hue says which company, matching the bubble the dot sits in.
                    // A placeholder is drawn hollow instead — desaturating it would collide
                    // with grey already meaning "no employer", and an outline reads as
                    // "not yet known" in any colour.
                    .foregroundStyle(person.placeholder ? Theme.bgPrimary : hue)
                    .stroke(
                        isSelected ? Theme.textNormal : (person.placeholder ? hue : Theme.bgPrimary),
                        StrokeStyle(lineWidth: isSelected ? 2.5 : 1.5)
                    )
                    .annotation(
                        Text(person.displayName)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.textMuted),
                        alignment: .bottom,
                        offset: CGVector(dx: 0, dy: 3)
                    )
            }

            // Directional: a relation belongs to whoever declared it.
            Series(relationEdges) { edge in
                LinkMark(from: edge.source, to: edge.target)
                    .stroke(
                        Theme.accent.opacity(0.75),
                        StrokeStyle(lineWidth: 1.6, lineCap: .round)
                    )
                    .linkShape(.arrow)
            }
        } force: {
            // Anchors do the grouping, so `center()` is gone — it would fight them by
            // pulling every cluster back toward the middle — and `manyBody` repulsion is
            // weaker than it was, since it now only has to spread nodes inside a cluster.
            //
            // Link springs are varied by whether the two people share an employer. Within a
            // company, full strength: relations are what shape the cluster. Across companies,
            // slack and long, so the arrow still draws without hauling either dot out of the
            // bubble that names it.
            .link(
                originalLength: .varied { edge, _ in
                    layout.isWithinOneCompany(edge.source, edge.target) ? 60 : 260
                },
                stiffness: .weightedByDegree { edge, _ in
                    layout.isWithinOneCompany(edge.source, edge.target) ? 1 : 0.04
                }
            )
            .manyBody(strength: -110)
            .position(
                direction: .x,
                targetOnDirection: .varied { layout.anchor(for: $0).x },
                strength: .varied { layout.pull(for: $0) })
            .position(
                direction: .y,
                targetOnDirection: .varied { layout.anchor(for: $0).y },
                strength: .varied { layout.pull(for: $0) })
            .collide(radius: .constant(20))
        }
        .graphBackground { _ in
            bubbles(layout: layout)
        }
        .graphOverlay { proxy in
            // The same GeometryReader as the bubble background, because resolving a click
            // against a bubble means inverting the transform that drew it — which needs the
            // canvas size. Grape's own `proxy.obsoleteState.cgSize` keeps it internal.
            GeometryReader { geometry in
                // Click anywhere: resolve what's under the cursor and select it.
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { point in
                        // A dot wins over the bubble it sits inside: the person is the more
                        // specific thing you were aiming at.
                        if let id = proxy.node(of: EntityID.self, near: point) {
                            selection = id
                        } else if let id = bubbleID(at: point, in: geometry.size, layout: layout) {
                            selection = id
                        }
                    }
                    // A node or a company bubble is clickable, the canvas around them isn't,
                    // and nothing about a painted circle says which — so the cursor has to.
                    .onContinuousHover { phase in
                        let isOverTarget: Bool
                        switch phase {
                        case .active(let point):
                            isOverTarget =
                                proxy.node(of: EntityID.self, near: point) != nil
                                || bubbleID(at: point, in: geometry.size, layout: layout) != nil
                        case .ended:
                            isOverTarget = false
                        }
                        guard isOverTarget != isHoveringTarget else { return }
                        isHoveringTarget = isOverTarget
                        if isOverTarget {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    // Dragging only takes effect while the simulation ticks, so run it for
                    // the duration of the drag and settle again on release.
                    .withGraphDragGesture(proxy, of: EntityID.self) { dragState in
                        graphState.isRunning = dragState != nil
                    }
                    .withGraphMagnifyGesture(proxy)
            }
        }
    }

    // MARK: Bubbles

    /// One tinted circle per employer, drawn behind the graph.
    ///
    /// Grape composes its render transform as `modelTransform.translate(by: size / 2)`, so
    /// reproducing that here is what keeps a bubble locked to its dots through pan and zoom.
    /// Labels keep a fixed point size rather than scaling with the zoom, matching how Grape
    /// rasterizes its own node annotations, so a company stays named at every scale.
    private func bubbles(layout: ClusterLayout) -> some View {
        GeometryReader { geometry in
            let transform = graphState.modelTransform
            let scale = transform.scale
            let origin = CGPoint(
                x: transform.translate.x + geometry.size.width / 2,
                y: transform.translate.y + geometry.size.height / 2)

            ForEach(layout.bubbles) { bubble in
                let diameter = bubble.radius * 2 * scale
                let isSelected = bubble.id != nil && bubble.id == selection

                Circle()
                    .fill(bubble.color.opacity(0.10))
                    .overlay(
                        Circle().strokeBorder(
                            bubble.color.opacity(isSelected ? 0.9 : 0.45),
                            lineWidth: isSelected ? 2 : Theme.hairline)
                    )
                    .frame(width: diameter, height: diameter)
                    .overlay(alignment: .top) {
                        bubbleLabel(bubble)
                            // Sits just inside the rim, so it never collides with the dots
                            // gathered at the centre.
                            .padding(.top, Theme.Spacing.small)
                    }
                    .position(
                        x: origin.x + bubble.center.x * scale,
                        y: origin.y + bubble.center.y * scale)
            }
        }
        // Hit-testing lives in the overlay, so exactly one layer resolves a click.
        .allowsHitTesting(false)
    }

    private func bubbleLabel(_ bubble: ClusterLayout.Bubble) -> some View {
        VStack(spacing: 0) {
            Text(bubble.organization?.displayName ?? "No employer")
                .font(Theme.Font.heading)
                .foregroundStyle(Theme.textNormal)
            Text("\(bubble.headcount)")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textMuted)
        }
        .lineLimit(1)
    }

    /// The organization whose bubble contains `point`, in view coordinates.
    ///
    /// Inverts the same transform ``bubbles(layout:)`` applies. Returns `nil` for the
    /// unaffiliated bubble, which has no entity to select.
    private func bubbleID(at point: CGPoint, in size: CGSize, layout: ClusterLayout)
        -> EntityID?
    {
        let transform = graphState.modelTransform
        guard transform.scale != 0 else { return nil }
        let simulationPoint = SIMD2<Double>(
            x: (point.x - transform.translate.x - size.width / 2) / transform.scale,
            y: (point.y - transform.translate.y - size.height / 2) / transform.scale)
        return layout.bubble(at: simulationPoint)?.id
    }

    // MARK: Legend

    /// Only the hollow-dot convention needs explaining now.
    ///
    /// The old rows are gone because both became false: there are no organization nodes to
    /// key, and a dot is no longer one colour — a hue means "this employer", which each
    /// bubble states on itself far better than a swatch could. Shown only when the vault has
    /// placeholders, so an empty legend never floats over the graph.
    @ViewBuilder
    private var legend: some View {
        if store.allPeople.contains(where: \.placeholder) {
            HStack(spacing: Theme.Spacing.small) {
                Circle()
                    .fill(Theme.bgPrimary)
                    .overlay(Circle().strokeBorder(Theme.textFaint, lineWidth: 1.5))
                    .frame(width: 8, height: 8)
                Text("Unnamed")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(Theme.Spacing.small)
            .background(Theme.bgSecondary.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium)
                    .stroke(Theme.border, lineWidth: Theme.hairline)
            )
            .padding(Theme.Spacing.medium)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .allowsHitTesting(false)
        }
    }

    // MARK: Edge derivation

    private struct Edge: Hashable {
        let source: EntityID
        let target: EntityID
    }

    /// Person → person relation edges, taken from the source's stored relations.
    /// Dangling targets are skipped so a deleted person can't crash the layout.
    private var relationEdges: [Edge] {
        var edges: [Edge] = []
        for person in store.allPeople {
            for relation in person.relations
            where store.snapshot.people[relation.to.id] != nil {
                edges.append(Edge(source: person.id, target: relation.to.id))
            }
        }
        return edges
    }

    /// Every node is a person now, so one size serves. Sizing by importance is the bubble's
    /// job — it grows with headcount.
    private static let personRadius: CGFloat = 7
}

// MARK: - Forgiving hit testing

extension GraphProxy {
    /// How far off a node's edge still counts as hitting it, in points.
    ///
    /// A person's circle is 14pt across. Grape's own `node(of:at:)` tests the drawn radius
    /// exactly, so a click a few points off centre — well inside what a pointer can
    /// reasonably be asked to hit — returned nil and the node looked dead. Mouse targets
    /// want ~20pt; this pads the small ones up to that without inflating an org node, whose
    /// circle is already large.
    private static let slop: CGFloat = 8

    /// The node at `point`, or the nearest one within ``slop`` of it.
    ///
    /// Grape exposes only an exact test, so this samples it on a ring of offsets around the
    /// point: cheap, needs no access to node positions, and picks the node whose edge is
    /// closest because it tries the smallest offsets first. Ties go to whatever Grape's own
    /// reverse iteration prefers, which is the topmost drawn node.
    @MainActor
    func node<ID: Hashable>(of type: ID.Type, near point: CGPoint) -> ID? {
        if let hit = node(of: type, at: point) { return hit }

        let directions = 8
        // Two rings rather than one: a single ring at full slop skips a node that sits
        // between the samples, and stepping finer than this buys nothing at 8pt.
        for distance in stride(from: Self.slop / 2, through: Self.slop, by: Self.slop / 2) {
            for step in 0..<directions {
                let angle = 2 * CGFloat.pi * CGFloat(step) / CGFloat(directions)
                let probe = CGPoint(
                    x: point.x + cos(angle) * distance,
                    y: point.y + sin(angle) * distance)
                if let hit = node(of: type, at: probe) { return hit }
            }
        }
        return nil
    }
}

// MARK: - Cluster layout

/// Assigns every person a fixed anchor point, one per employer, and sizes the bubble drawn
/// around each cluster.
///
/// Groups sit on a ring, spaced by index, which is what makes the layout reproducible: the
/// store returns organizations in a stable order with the unaffiliated bucket last, so
/// "Acme is up and to the right" stays true between launches — and so does its colour.
///
/// The bubble's centre *is* the group's anchor, which is why this type owns both. Grape never
/// exposes settled node positions, so a hull hugging the dots isn't available; drawing at the
/// anchor is not merely the workaround but the steadier picture, since it cannot drift as the
/// simulation settles.
struct ClusterLayout {
    /// How far the first ring sits from the centre, in simulation units.
    private static let baseRadius: Double = 130
    /// Added per group beyond the first few, so ten clusters aren't packed as tightly as
    /// three.
    private static let radiusPerGroup: Double = 26

    /// Bubble radius for a one-person company — below this a bubble stops reading as a
    /// container and starts reading as a big dot.
    static let minBubbleRadius: Double = 46
    /// Ceiling, so one large employer can't swallow the canvas.
    static let maxBubbleRadius: Double = 130
    /// Clear space guaranteed between two neighbouring bubbles' edges.
    static let bubbleGap: Double = 34

    /// A drawn cluster: where its bubble sits, how big it is, and what labels it.
    struct Bubble: Identifiable {
        /// The organization's id, or `nil` for the unaffiliated bucket — which is also what
        /// makes that bubble unselectable, since there is no entity to select.
        let id: EntityID?
        let organization: Organization?
        /// Simulation units; the group's anchor.
        let center: SIMD2<Double>
        /// Simulation units.
        let radius: Double
        let color: Color
        let headcount: Int
    }

    /// Where each person is pulled toward, by entity id.
    private let anchors: [EntityID: SIMD2<Double>]
    /// Which cluster each person belongs to, by entity id. Absent means the unaffiliated
    /// bucket, which is a real group with a real bubble but no palette hue.
    private let groupIndices: [EntityID: Int]

    /// The people drawn as nodes. Organizations are no longer nodes — their bubble says
    /// everything the node did, and more.
    let nodes: [Person]
    let bubbles: [Bubble]

    init(groups: [(organization: Organization?, people: [Person])]) {
        // Radii first: the ring has to be wide enough for the *largest* bubble, so it can't
        // be computed until every headcount is known.
        let radii = groups.map { Self.bubbleRadius(headcount: $0.people.count) }
        let ringRadius = Self.ringRadius(groupCount: groups.count, bubbleRadii: radii)

        var anchors: [EntityID: SIMD2<Double>] = [:]
        var groupIndices: [EntityID: Int] = [:]
        var nodes: [Person] = []
        var bubbles: [Bubble] = []

        for (index, group) in groups.enumerated() {
            let anchor = Self.anchor(index: index, groupCount: groups.count, ringRadius: ringRadius)

            for person in group.people {
                nodes.append(person)
                anchors[person.id] = anchor
                if group.organization != nil { groupIndices[person.id] = index }
            }

            bubbles.append(
                Bubble(
                    id: group.organization?.id,
                    organization: group.organization,
                    center: anchor,
                    radius: radii[index],
                    color: Theme.clusterColor(at: group.organization == nil ? nil : index),
                    headcount: group.people.count
                ))
        }

        self.anchors = anchors
        self.groupIndices = groupIndices
        self.nodes = nodes
        self.bubbles = bubbles
    }

    // MARK: Geometry

    /// A single group has nowhere to spread to, so centre it rather than pushing it off to
    /// one side of an otherwise empty canvas.
    static func anchor(index: Int, groupCount: Int, ringRadius: Double) -> SIMD2<Double> {
        guard groupCount > 1 else { return .zero }
        let angle = (2 * Double.pi * Double(index)) / Double(groupCount)
        return SIMD2(ringRadius * cos(angle), ringRadius * sin(angle))
    }

    /// Grows with headcount, but on a square root: *area* should track the number of people,
    /// otherwise a ten-person company looks ten times the company a one-person one is.
    static func bubbleRadius(headcount: Int) -> Double {
        let grown = minBubbleRadius + 17 * (Double(max(headcount, 1)) - 1).squareRoot()
        return min(grown, maxBubbleRadius)
    }

    /// Wide enough that neighbouring bubbles always clear each other.
    ///
    /// Two anchors adjacent on a ring of radius `R` sit `2 * R * sin(π / n)` apart, so
    /// solving that for the largest bubble's diameter plus a gap gives the minimum ring that
    /// cannot overlap. Taken as a floor under the old count-based formula, which knew nothing
    /// about how big the bubbles it was spacing actually were.
    static func ringRadius(groupCount: Int, bubbleRadii: [Double]) -> Double {
        guard groupCount > 1 else { return 0 }
        let spread = baseRadius + radiusPerGroup * Double(max(0, groupCount - 3))
        let largest = bubbleRadii.max() ?? minBubbleRadius
        let required = (largest + bubbleGap / 2) / sin(Double.pi / Double(groupCount))
        return max(spread, required)
    }

    // MARK: Lookups

    func anchor(for id: EntityID) -> SIMD2<Double> {
        anchors[id] ?? .zero
    }

    /// How hard a person is held to their cluster's centre.
    ///
    /// Firm rather than loose: a dot outside the bubble that names it would contradict the
    /// picture, so containment — not suggestion — is the point. Cross-company relations are
    /// weakened at the spring instead (see the `force:` builder), which keeps them visible
    /// without letting them drag anyone out.
    func pull(for id: EntityID) -> Double {
        anchors[id] == nil ? 0 : 0.45
    }

    /// Which cluster a person belongs to, by index, or `nil` for the unaffiliated bucket.
    /// Drives both the dot's hue and the same-company test the link forces need.
    func groupIndex(for id: EntityID) -> Int? {
        groupIndices[id]
    }

    /// Whether two people share an employer, which decides how stiff the spring between them
    /// is. Two *unaffiliated* people count as apart: they share a bubble but not a company, so
    /// there's no cluster shape for a strong spring to help form.
    func isWithinOneCompany(_ a: EntityID, _ b: EntityID) -> Bool {
        guard let left = groupIndices[a], let right = groupIndices[b] else { return false }
        return left == right
    }

    /// The bubble containing `point` (simulation units), smallest first so a nested bubble
    /// would win, or `nil` out on the canvas.
    func bubble(at point: SIMD2<Double>) -> Bubble? {
        bubbles
            .filter { (point - $0.center).length <= $0.radius }
            .min { $0.radius < $1.radius }
    }
}

extension SIMD2 where Scalar == Double {
    /// Distance from the origin. Grape keeps its own SIMD helpers `internal`, so this is
    /// spelled out here rather than imported.
    var length: Double { (x * x + y * y).squareRoot() }
}
