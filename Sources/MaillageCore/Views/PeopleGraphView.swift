import Grape
import SwiftUI

/// Everyone in the vault as a network, grouped into one cluster per employer.
///
/// Nodes are people and organizations only — projects belong to the other two centre-pane
/// views, and dropping them is what turns a hairball back into something readable. The one
/// kind of edge drawn is a person → person **relation**, with an arrowhead because it is
/// one-way; membership needs no edge, because it's expressed by which cluster someone
/// sits in.
///
/// Clustering is done by pinning each group to a point on a ring and pulling its members
/// toward it, rather than by letting repulsion sort things out. Springs alone don't
/// separate groups — they interleave, and the result differs on every launch. Anchors are
/// derived from the group's *index*, so the same vault lays out the same way every time
/// and the picture becomes memorable.
struct PeopleGraphView: View {
    @Environment(VaultStore.self) private var store
    @Binding var selection: EntityID?

    // A perpetually running simulation re-renders at 60 fps and starves text input
    // everywhere in the app, so settle the layout once on appear and stay idle.
    @State private var graphState = ForceDirectedGraphState(
        initialIsRunning: false,
        ticksOnAppear: .untilStable)

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

    // MARK: Graph

    private var graph: some View {
        // Recomputing the node/edge lists once per render keeps the GraphContent
        // builder cheap and avoids repeated dictionary lookups inside it.
        let layout = ClusterLayout(groups: store.peopleGroupedByOrganization())
        let nodes = layout.nodes
        let relationEdges = self.relationEdges

        return ForceDirectedGraph(states: graphState) {
            Series(nodes) { entity in
                NodeMark(id: entity.id)
                    .symbolSize(radius: radius(for: entity))
                    .foregroundStyle(Theme.color(for: entity))
                    .stroke(
                        entity.id == selection ? Theme.textNormal : Theme.bgPrimary,
                        StrokeStyle(lineWidth: entity.id == selection ? 2.5 : 1)
                    )
                    .annotation(
                        Text(entity.displayName)
                            .font(entity.kind == .organization ? Theme.Font.heading : Theme.Font.caption)
                            .foregroundStyle(
                                entity.kind == .organization ? Theme.textNormal : Theme.textMuted),
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
            .link(originalLength: .constant(60))
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
        .graphOverlay { proxy in
            // Click anywhere: resolve the node under the cursor and select it.
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .withGraphTapGesture(proxy, of: EntityID.self) { id in
                    selection = id
                }
                // Dragging only takes effect while the simulation ticks, so run it for
                // the duration of the drag and settle again on release.
                .withGraphDragGesture(proxy, of: EntityID.self) { dragState in
                    graphState.isRunning = dragState != nil
                }
                .withGraphMagnifyGesture(proxy)
        }
    }

    // MARK: Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            legendRow(color: Theme.personColor, label: "People")
            legendRow(color: Theme.organizationColor, label: "Organizations")
            if store.allPeople.contains(where: \.placeholder) {
                legendRow(color: Theme.placeholderColor, label: "Unnamed")
            }
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

    private func legendRow(color: Color, label: String) -> some View {
        HStack(spacing: Theme.Spacing.small) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textMuted)
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

    /// An organization reads as its cluster's label, so it is drawn larger, and grows
    /// with how many people it holds.
    private func radius(for entity: AnyEntity) -> CGFloat {
        switch entity {
        case .person:
            return 7
        case .organization(let org):
            return 9 + min(CGFloat(store.members(ofOrganization: org.id).count), 6)
        case .project:
            return 8  // Not drawn in this view; here so the switch stays exhaustive.
        }
    }
}

// MARK: - Cluster layout

/// Assigns every node a fixed anchor point, one per employer.
///
/// Groups sit on a ring, spaced by index, which is what makes the layout reproducible: the
/// store returns organizations in a stable order with the unaffiliated bucket last, so
/// "Acme is up and to the right" stays true between launches. The ring's radius grows with
/// the group count so clusters don't crowd as a vault fills up.
private struct ClusterLayout {
    /// How far the first ring sits from the centre, in simulation units.
    private static let baseRadius: Double = 130
    /// Added per group beyond the first few, so ten clusters aren't packed as tightly as
    /// three.
    private static let radiusPerGroup: Double = 26

    /// Where each node is pulled toward, by entity id.
    private let anchors: [EntityID: SIMD2<Double>]
    /// How hard, by entity id. Organizations are held much harder than their members:
    /// the label should stay put at the cluster's centre while people arrange themselves
    /// around it according to their relations.
    private let pulls: [EntityID: Double]

    /// People and organizations, organizations last so their labels draw on top.
    let nodes: [AnyEntity]

    init(groups: [(organization: Organization?, people: [Person])]) {
        let ringRadius =
            Self.baseRadius + Self.radiusPerGroup * Double(max(0, groups.count - 3))

        var anchors: [EntityID: SIMD2<Double>] = [:]
        var pulls: [EntityID: Double] = [:]
        var people: [AnyEntity] = []
        var organizations: [AnyEntity] = []

        for (index, group) in groups.enumerated() {
            // A single group has nowhere to spread to, so centre it rather than pushing it
            // off to one side of an otherwise empty canvas.
            let angle =
                groups.count == 1
                ? 0
                : (2 * Double.pi * Double(index)) / Double(groups.count)
            let anchor =
                groups.count == 1
                ? SIMD2<Double>(0, 0)
                : SIMD2(ringRadius * cos(angle), ringRadius * sin(angle))

            if let organization = group.organization {
                organizations.append(.organization(organization))
                anchors[organization.id] = anchor
                pulls[organization.id] = 0.9
            }
            for person in group.people {
                people.append(.person(person))
                anchors[person.id] = anchor
                // Loose enough that a relation across two clusters visibly bends the two
                // people toward each other — the pull is a grouping hint, not a cage.
                pulls[person.id] = 0.12
            }
        }

        self.anchors = anchors
        self.pulls = pulls
        self.nodes = people + organizations
    }

    func anchor(for id: EntityID) -> SIMD2<Double> {
        anchors[id] ?? .zero
    }

    func pull(for id: EntityID) -> Double {
        pulls[id] ?? 0
    }
}
