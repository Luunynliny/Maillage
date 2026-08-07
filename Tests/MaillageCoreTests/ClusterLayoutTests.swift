import Foundation
import Testing

@testable import MaillageCore

/// Builds the group shape `VaultStore.peopleGroupedByOrganization()` returns, without a vault:
/// the layout is pure geometry, so it can be exercised directly.
private func groups(_ headcounts: [Int], unaffiliated: Int = 0)
    -> [(organization: Organization?, people: [Person])]
{
    var result: [(organization: Organization?, people: [Person])] = []
    for (index, count) in headcounts.enumerated() {
        let org = Organization(id: "org-\(index)", name: "Org \(index)")
        let people = (0..<count).map { Person(id: "p-\(index)-\($0)", firstname: "P\($0)") }
        result.append((org, people))
    }
    if unaffiliated > 0 {
        result.append((nil, (0..<unaffiliated).map { Person(id: "free-\($0)") }))
    }
    return result
}

@Suite("Cluster layout")
struct ClusterLayoutTests {
    @Test("Draws one bubble per group, unaffiliated last")
    func oneBubblePerGroup() throws {
        let layout = ClusterLayout(groups: groups([3, 2], unaffiliated: 1))

        #expect(layout.bubbles.count == 3)
        #expect(layout.bubbles.map(\.id) == ["org-0", "org-1", nil])
        #expect(layout.bubbles.map(\.headcount) == [3, 2, 1])
        // Everyone is a node, including the unaffiliated.
        #expect(layout.nodes.count == 6)
    }

    /// The invariant the ring-radius change exists to guarantee. Asserted across a range of
    /// counts and lopsided headcounts, since the failure mode is one big company crowding a
    /// neighbour rather than anything that shows up at a single size.
    @Test("Never overlaps two bubbles", arguments: 1...12)
    func bubblesNeverOverlap(groupCount: Int) throws {
        // One outsized employer beside a crowd of tiny ones — the worst case for spacing.
        var headcounts = Array(repeating: 1, count: groupCount)
        headcounts[0] = 20
        let layout = ClusterLayout(groups: groups(headcounts))

        for (i, a) in layout.bubbles.enumerated() {
            for b in layout.bubbles[(i + 1)...] {
                let distance = (a.center - b.center).length
                #expect(
                    distance >= a.radius + b.radius,
                    "bubbles \(i) and \(b.id ?? "?") overlap at \(groupCount) groups")
            }
        }
    }

    @Test("Centres a lone group instead of pushing it aside")
    func singleGroupIsCentred() throws {
        let layout = ClusterLayout(groups: groups([4]))

        #expect(layout.bubbles.count == 1)
        #expect(layout.bubbles[0].center == .zero)
    }

    @Test("Grows the bubble with headcount, within its clamp")
    func radiusGrowsAndClamps() throws {
        let one = ClusterLayout.bubbleRadius(headcount: 1)
        let five = ClusterLayout.bubbleRadius(headcount: 5)
        let huge = ClusterLayout.bubbleRadius(headcount: 5000)

        #expect(one == ClusterLayout.minBubbleRadius)
        #expect(five > one)
        #expect(huge == ClusterLayout.maxBubbleRadius)
        // An empty group would still be drawable, rather than collapsing to a point.
        #expect(ClusterLayout.bubbleRadius(headcount: 0) == ClusterLayout.minBubbleRadius)
    }

    /// Reproducibility is the whole reason anchors come from the group's index: "Acme is up
    /// and to the right" has to stay true between launches, and so does its colour.
    @Test("Lays out identically when rebuilt")
    func layoutIsDeterministic() throws {
        let input = groups([3, 1, 4], unaffiliated: 2)
        let first = ClusterLayout(groups: input)
        let second = ClusterLayout(groups: input)

        #expect(first.bubbles.map(\.center) == second.bubbles.map(\.center))
        #expect(first.bubbles.map(\.radius) == second.bubbles.map(\.radius))
        #expect(first.bubbles.map(\.color) == second.bubbles.map(\.color))
        #expect(first.nodes.map(\.id) == second.nodes.map(\.id))
    }

    @Test("Reports the group a person was placed in")
    func groupIndexAgreesWithPlacement() throws {
        let layout = ClusterLayout(groups: groups([2, 1], unaffiliated: 1))

        #expect(layout.groupIndex(for: "p-0-0") == 0)
        #expect(layout.groupIndex(for: "p-0-1") == 0)
        #expect(layout.groupIndex(for: "p-1-0") == 1)
        // The unaffiliated bucket has a bubble but no company, so no palette hue.
        #expect(layout.groupIndex(for: "free-0") == nil)
        #expect(layout.groupIndex(for: "nobody") == nil)
    }

    /// The dot-to-bubble colour correspondence *is* the tint feature: if a person's hue and
    /// their bubble's hue could disagree, the grouping would be actively misleading.
    @Test("Tints every person to match their own bubble")
    func personHueMatchesBubble() throws {
        let input = groups([2, 3], unaffiliated: 1)
        let layout = ClusterLayout(groups: input)

        for (index, group) in input.enumerated() {
            let bubble = layout.bubbles[index]
            for person in group.people {
                let hue = Theme.clusterColor(at: layout.groupIndex(for: person.id))
                #expect(hue == bubble.color)
            }
        }
    }

    @Test("Cycles hues when a vault outgrows the palette")
    func paletteCycles() throws {
        let count = Theme.clusterPalette.count
        #expect(Theme.clusterColor(at: count) == Theme.clusterColor(at: 0))
        #expect(Theme.clusterColor(at: nil) == Theme.noClusterColor)

        // Chiefly a crash check: one bubble past the palette's end must still lay out.
        let layout = ClusterLayout(groups: groups(Array(repeating: 1, count: count + 2)))
        #expect(layout.bubbles.count == count + 2)
    }

    @Test("Treats only same-employer pairs as within one company")
    func withinOneCompany() throws {
        let layout = ClusterLayout(groups: groups([2, 1], unaffiliated: 2))

        #expect(layout.isWithinOneCompany("p-0-0", "p-0-1"))
        #expect(!layout.isWithinOneCompany("p-0-0", "p-1-0"))
        // Two unaffiliated people share a bubble but not a company, so their spring stays
        // slack — there's no cluster shape for a stiff one to help form.
        #expect(!layout.isWithinOneCompany("free-0", "free-1"))
    }

    @Test("Resolves a point to the bubble containing it")
    func bubbleHitTesting() throws {
        let layout = ClusterLayout(groups: groups([3, 3]))
        let first = try #require(layout.bubbles.first)

        #expect(layout.bubble(at: first.center)?.id == first.id)
        // Just inside the rim hits; just outside it misses.
        #expect(layout.bubble(at: first.center + SIMD2(first.radius - 1, 0))?.id == first.id)
        let farAway = first.center + SIMD2(first.radius * 100, first.radius * 100)
        #expect(layout.bubble(at: farAway) == nil)
    }
}
