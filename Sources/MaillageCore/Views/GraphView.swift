import Grape
import SwiftUI

/// The Obsidian-style network view of the whole vault.
///
/// Nodes are people, organizations and projects, coloured by kind. Two kinds of edge
/// are drawn:
/// - **Relations** (person → person) get an arrowhead, because they are one-way.
/// - **Membership** (person → org/project) is undirected and drawn dimmer, so the
///   directional relations stay visually dominant.
public struct GraphView: View {
    @Environment(VaultStore.self) private var store
    @Binding var selection: EntityID?

    // A perpetually running simulation re-renders at 60 fps and starves text input
    // everywhere in the app, so settle the layout once on appear and stay idle.
    @State private var graphState = ForceDirectedGraphState(
        initialIsRunning: false,
        ticksOnAppear: .untilStable)

    public init(selection: Binding<EntityID?>) {
        self._selection = selection
    }

    public var body: some View {
        ZStack {
            Theme.bgPrimary.ignoresSafeArea()

            if store.allEntities.isEmpty {
                EmptyStateView(
                    icon: "point.3.filled.connected.trianglepath.dotted",
                    title: "Nothing to graph yet",
                    message:
                        "Create a few people, organizations and relations and they'll appear here as a network."
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
        let nodes = store.allEntities
        let relationEdges = self.relationEdges
        let membershipEdges = self.membershipEdges

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

            // Non-directional membership, deliberately quieter.
            Series(membershipEdges) { edge in
                LinkMark(from: edge.source, to: edge.target)
                    .stroke(
                        Theme.borderStrong.opacity(0.55),
                        StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
            }
        } force: {
            // Repulsion plus collision keeps labels from overlapping at this node size.
            .link(originalLength: .constant(72))
            .manyBody(strength: -220)
            .center()
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
            ForEach(EntityKind.allCases, id: \.self) { kind in
                legendRow(color: Theme.color(for: kind), label: kind.displayName)
            }
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

    /// Person → org/project and project → org edges. Dangling links are skipped so a
    /// deleted target can't crash the layout.
    private var membershipEdges: [Edge] {
        var edges: [Edge] = []
        for person in store.allPeople {
            for org in person.organizations
            where store.snapshot.organizations[org.id] != nil {
                edges.append(Edge(source: person.id, target: org.id))
            }
            for project in person.projects
            where store.snapshot.projects[project.id] != nil {
                edges.append(Edge(source: person.id, target: project.id))
            }
        }
        for project in store.allProjects {
            for org in project.organizations
            where store.snapshot.organizations[org.id] != nil {
                edges.append(Edge(source: project.id, target: org.id))
            }
        }
        return edges
    }

    /// Organizations and projects read as hubs, so they are drawn larger; a hub's size
    /// also grows with how many people it holds.
    private func radius(for entity: AnyEntity) -> CGFloat {
        switch entity {
        case .person:
            return 7
        case .organization(let org):
            return 9 + min(CGFloat(store.members(ofOrganization: org.id).count), 6)
        case .project(let project):
            return 8 + min(CGFloat(store.members(ofProject: project.id).count), 5)
        }
    }
}
