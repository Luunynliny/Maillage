import Foundation
import SwiftUI
import Testing

@testable import MaillageCore

/// The arc shape `OrganizationRingView` hands the layout, built without a vault.
private func arc(_ label: String, _ names: [String], color: Color = Theme.clusterColor(at: 0))
    -> (label: String, people: [Person], color: Color)
{
    (label, names.map { Person(id: $0, firstname: $0) }, color)
}

private let pane = CGSize(width: 900, height: 700)

@Suite("Ring layout")
struct RingLayoutTests {
    @Test("Places every person once, on the rim")
    func onePerPersonOnTheRim() throws {
        let layout = RingLayout(
            arcs: [arc("Atlas", ["a", "b"]), arc("Maillage", ["c"])], in: pane)

        #expect(layout.nodes.count == 3)
        #expect(Set(layout.nodes.map(\.id)) == ["a", "b", "c"])
        for node in layout.nodes {
            #expect(abs(node.center.distance(to: layout.center) - layout.radius) < 0.001)
        }
    }

    /// A dot has to mean one person. Somebody on two projects is handed in as their own group
    /// rather than duplicated, and the layout must not undo that.
    @Test("Never draws the same person twice")
    func noDuplicates() throws {
        let layout = RingLayout(
            arcs: [
                arc("Atlas", ["a"]), arc("Maillage", ["b"]), arc("On several", ["c"]),
                arc("On no project", ["d"]),
            ], in: pane)

        #expect(layout.nodes.count == 4)
        #expect(Set(layout.nodes.map(\.id)).count == 4)
    }

    @Test("Keeps the arcs in the order they were given")
    func preservesArcOrder() throws {
        let layout = RingLayout(
            arcs: [arc("Atlas", ["a"]), arc("Maillage", ["b"]), arc("Outside", ["c"])],
            in: pane)

        #expect(layout.arcs.map(\.label) == ["Atlas", "Maillage", "Outside"])
        // Angles advance with the order, so the labels read round the ring the way they were
        // listed rather than in an order that depends on headcount.
        #expect(layout.arcs.map(\.startAngle).sorted() == layout.arcs.map(\.startAngle))
    }

    /// Gaps are the only thing distinguishing one group from the next — every arc of a company
    /// shares its hue, so an overlap would silently merge two projects.
    @Test("Leaves a gap between arcs and never overlaps them")
    func arcsDoNotOverlap() throws {
        let layout = RingLayout(
            arcs: [arc("A", ["a", "b", "c"]), arc("B", ["d"]), arc("C", ["e", "f"])],
            in: pane)

        for (index, arc) in layout.arcs.enumerated().dropLast() {
            let next = layout.arcs[index + 1]
            #expect(arc.endAngle < next.startAngle)
            #expect(next.startAngle - arc.endAngle >= RingLayout.arcGap - 0.001)
        }
        // The whole ring, gaps included, stays within one turn.
        #expect((layout.arcs.last?.endAngle ?? 0) <= 2 * CGFloat.pi + 0.001)
    }

    @Test("Keeps each person inside their own arc's extent")
    func nodesStayInTheirArc() throws {
        let layout = RingLayout(
            arcs: [arc("A", ["a", "b"]), arc("B", ["c", "d", "e"])], in: pane)

        for (index, arc) in layout.arcs.enumerated() {
            for id in arc.personIDs {
                #expect(layout.arcIndex(of: id) == index)
                let node = try #require(layout.node(id: id))
                // Recover the node's angle from its position and check it sits in the slice.
                let angle = atan2(
                    node.center.x - layout.center.x, layout.center.y - node.center.y)
                let normalized = angle < 0 ? angle + 2 * CGFloat.pi : angle
                #expect(normalized >= arc.startAngle - 0.001)
                #expect(normalized <= arc.endAngle + 0.001)
            }
        }
    }

    /// Every person gets the same slice of the circle, so a one-person arc can't be spaced as
    /// widely as a six-person one — otherwise the ring misreports how many are where.
    @Test("Sizes each arc by its headcount")
    func arcExtentTracksHeadcount() throws {
        let layout = RingLayout(arcs: [arc("A", ["a", "b", "c", "d"]), arc("B", ["e"])], in: pane)
        let big = try #require(layout.arcs.first)
        let small = try #require(layout.arcs.last)

        let bigExtent = big.endAngle - big.startAngle
        let smallExtent = small.endAngle - small.startAngle
        #expect(abs(bigExtent / smallExtent - 4) < 0.01)
    }

    /// A lone person should sit under the label naming their group, not on the boundary with
    /// the next one.
    @Test("Centres a lone person under their arc's label")
    func lonePersonSitsAtArcMiddle() throws {
        let layout = RingLayout(arcs: [arc("A", ["a"]), arc("B", ["b"])], in: pane)
        let first = try #require(layout.arcs.first)
        let node = try #require(layout.node(id: "a"))
        let expected = CGPoint.onCircle(
            center: layout.center, radius: layout.radius, angle: first.midAngle)

        #expect(node.center.distance(to: expected) < 0.001)
    }

    /// The view splits "Outside" into one entry per person so each can carry its own employer's
    /// hue; merging them back is what keeps the label drawn once over the whole run.
    @Test("Merges consecutive arcs sharing a label")
    func mergesRunsOfOneLabel() throws {
        let layout = RingLayout(
            arcs: [
                arc("Atlas", ["a"]),
                arc("Outside", ["x"], color: Theme.clusterColor(at: 1)),
                arc("Outside", ["y"], color: Theme.clusterColor(at: 2)),
            ], in: pane)

        #expect(layout.arcs.map(\.label) == ["Atlas", "Outside"])
        #expect(layout.arcs.last?.personIDs == ["x", "y"])
        // Each outsider keeps their own employer's hue inside the merged arc.
        #expect(layout.node(id: "x")?.color == Theme.clusterColor(at: 1))
        #expect(layout.node(id: "y")?.color == Theme.clusterColor(at: 2))
    }

    @Test("Draws a placeholder hollow")
    func placeholderIsHollow() throws {
        let named = Person(id: "a", firstname: "A")
        let unnamed = Person(id: "_cfo", placeholder: true, descriptor: "The CFO")
        let layout = RingLayout(
            arcs: [("Outside", [named, unnamed], Theme.clusterColor(at: 0))], in: pane)

        #expect(layout.node(id: "a")?.isHollow == false)
        #expect(layout.node(id: "_cfo")?.isHollow == true)
        // A placeholder is still named by its descriptor rather than its filename.
        #expect(layout.node(id: "_cfo")?.label == "The CFO")
    }

    @Test("Lays out identically when rebuilt")
    func layoutIsDeterministic() throws {
        let input = [arc("A", ["a", "b"]), arc("B", ["c"]), arc("C", ["d", "e", "f"])]
        let first = RingLayout(arcs: input, in: pane)
        let second = RingLayout(arcs: input, in: pane)

        #expect(first.nodes.map(\.id) == second.nodes.map(\.id))
        #expect(first.nodes.map(\.center) == second.nodes.map(\.center))
        #expect(first.arcs.map(\.startAngle) == second.arcs.map(\.startAngle))
    }

    /// A one-person company with no projects is a real vault state — the ring degenerating to a
    /// single dot must not crash or divide by zero.
    @Test("Degenerates to one node for a one-person company")
    func singlePerson() throws {
        let layout = RingLayout(arcs: [arc("On no project", ["a"])], in: pane)

        #expect(layout.nodes.count == 1)
        #expect(layout.arcs.count == 1)
        // With nothing to separate it from, the lone arc takes the whole circle.
        #expect(layout.arcs[0].startAngle == 0)
    }

    @Test("Handles no people without crashing")
    func emptyInput() throws {
        let layout = RingLayout(arcs: [], in: pane)

        #expect(layout.nodes.isEmpty)
        #expect(layout.arcs.isEmpty)
        #expect(layout.arcIndex(of: "nobody") == nil)
    }

    /// A name is horizontal text centred under its dot, so the rim has to clear the pane's
    /// sides by more than its top — sizing both off the smaller need pushed names off-pane.
    ///
    /// The margin is a ceiling, though, not a promise: on a narrow pane it's capped at a share
    /// of the pane, because a rim collapsed to its floor piles every dot and name into the
    /// middle, which is worse than a name reaching near the edge.
    @Test(
        "Leaves room for the names either side of the rim",
        arguments: [
            CGSize(width: 1400, height: 900),
            CGSize(width: 320, height: 700),
            CGSize(width: 900, height: 260),
        ])
    func rimFitsThePane(size: CGSize) throws {
        let layout = RingLayout(arcs: [arc("A", ["a", "b", "c"])], in: size)

        #expect(layout.radius > 0)
        // Never past the pane's edge, whichever of the two rules bound it.
        #expect(layout.radius <= min(size.width, size.height) / 2)
        let allowance = min(
            size.width / 2 - min(RingLayout.horizontalMargin, size.width * graphMarginShare),
            size.height / 2 - min(RingLayout.verticalMargin, size.height * graphMarginShare))
        #expect(abs(layout.radius - max(allowance, RingLayout.nodeRadius * 2)) < 0.001)
        #expect(RingLayout.horizontalMargin > RingLayout.verticalMargin)
    }

    /// The failure this cap exists for: a narrow pane used to fall through to the floor, which
    /// put every dot and every name on top of each other in the middle.
    @Test("Keeps the rim proportional on a narrow pane")
    func narrowPaneStillSpreadsTheRing() throws {
        let narrow = CGSize(width: 420, height: 380)
        let layout = RingLayout(arcs: [arc("A", ["a", "b", "c", "d"])], in: narrow)

        #expect(layout.radius > RingLayout.nodeRadius * 2)
        // Comfortably more than a third of the room available, so the arc still reads as a ring.
        #expect(layout.radius > min(narrow.width, narrow.height) / 2 * 0.6)
    }

    /// Because the rim is only pushed in as far as the pane can afford, an arc label's gap and
    /// width have to come from what's actually left — a fixed inset would start the word past
    /// the edge on a narrow pane.
    @Test(
        "Reports the room left for an arc label",
        arguments: [
            CGSize(width: 1400, height: 900),
            CGSize(width: 420, height: 380),
        ])
    func labelRoomMatchesWhatIsLeft(size: CGSize) throws {
        let layout = RingLayout(arcs: [arc("On no project", ["a", "b"])], in: size)

        #expect(abs(layout.labelRoom - (size.width / 2 - layout.radius)) < 0.001)
        #expect(layout.labelRoom > 0)
    }
}
