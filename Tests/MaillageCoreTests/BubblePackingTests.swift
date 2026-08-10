import Foundation
import SwiftUI
import Testing

@testable import MaillageCore

/// Builds the shape `VaultStore.peopleGroupedByOrganization()` returns, without a vault: the
/// packing is pure geometry, so it can be exercised directly.
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

private let pane = CGSize(width: 900, height: 700)

@Suite("Bubble packing")
struct BubblePackingTests {
    @Test("Draws one bubble per group")
    func oneBubblePerGroup() throws {
        let packing = BubblePacking(groups: groups([3, 2], unaffiliated: 1), in: pane)

        #expect(packing.bubbles.count == 3)
        #expect(packing.bubbles.map(\.headcount).reduce(0, +) == 6)
    }

    /// "No employer" isn't a company, so it must never be presented as the biggest one however
    /// many people are in it — and it must stay grey, since a palette hue would read as an
    /// employer.
    @Test("Sorts the unaffiliated bucket last and keeps it grey")
    func unaffiliatedIsLastAndGrey() throws {
        let packing = BubblePacking(groups: groups([2, 1], unaffiliated: 9), in: pane)
        let last = try #require(packing.bubbles.last)

        #expect(last.id == nil)
        #expect(last.headcount == 9)
        #expect(last.color == Theme.noClusterColor)
        #expect(last.name == "No employer")
        // Everything before it is a real company with something to select.
        #expect(packing.bubbles.dropLast().allSatisfy { $0.id != nil })
    }

    /// "Acme is the big one in the middle" — stated as *what the packing actually guarantees*,
    /// which is that the largest circle is placed first and every other one spirals around it.
    ///
    /// Not "the largest is nearest the pane centre", which this test used to assert. That is a
    /// side effect of the arrangement's shape rather than an invariant: ``BubblePacking/fit`` says
    /// it centres the packing's *bounding box*, and with a few similar-sized companies the box's
    /// middle can land nearer a smaller circle than the biggest one. The old assertion held for
    /// `[1, 7, 3]` and failed for `[3, 2, 1]` and `[4, 4, 1]` at the same time — so it was
    /// passing on the example rather than on the rule.
    @Test(
        "Surrounds the largest company with the rest",
        arguments: [[1, 7, 3], [3, 2, 1], [4, 4, 1], [1, 2, 3, 4], [12, 5, 3, 1, 1]])
    func largestIsSurrounded(headcounts: [Int]) throws {
        let packing = BubblePacking(groups: groups(headcounts), in: pane)
        let biggest = try #require(packing.bubbles.max { $0.headcount < $1.headcount })

        for bubble in packing.bubbles where bubble.id != biggest.id {
            // Wholly outside it — the spiral steps out from the first circle's rim, so nothing
            // later can encroach on the one the arrangement is built around.
            #expect(
                bubble.center.distance(to: biggest.center) >= biggest.radius + bubble.radius - 0.001
            )
        }
    }

    /// The invariant packing exists to satisfy. Asserted with one outsized employer beside a
    /// crowd of tiny ones, since the failure mode is a big circle swallowing a neighbour rather
    /// than anything that shows up at a single uniform size.
    @Test("Never overlaps two bubbles", arguments: 1...12)
    func bubblesNeverOverlap(groupCount: Int) throws {
        var headcounts = Array(repeating: 1, count: groupCount)
        headcounts[0] = 20
        let packing = BubblePacking(groups: groups(headcounts, unaffiliated: 2), in: pane)

        for (index, a) in packing.bubbles.enumerated() {
            for b in packing.bubbles[(index + 1)...] {
                #expect(
                    a.center.distance(to: b.center) >= a.radius + b.radius - 0.001,
                    "overlap at \(groupCount) groups")
            }
        }
    }

    /// Because the packing is scaled to fit, a bubble spilling off the edge is invisible rather
    /// than merely ugly — and a narrow pane is the shape that catches it.
    @Test(
        "Fits inside the pane at any shape",
        arguments: [
            CGSize(width: 1400, height: 900),
            CGSize(width: 380, height: 900),
            CGSize(width: 900, height: 320),
            CGSize(width: 300, height: 300),
        ])
    func fitsInsideThePane(size: CGSize) throws {
        let packing = BubblePacking(groups: groups([12, 5, 3, 1, 1], unaffiliated: 1), in: size)

        for bubble in packing.bubbles {
            #expect(bubble.center.x - bubble.radius >= -0.001)
            #expect(bubble.center.y - bubble.radius >= -0.001)
            #expect(bubble.center.x + bubble.radius <= size.width + 0.001)
            #expect(bubble.center.y + bubble.radius <= size.height + 0.001)
        }
    }

    /// Area, not radius, is what the eye reads as "how many" — so a four-person company must
    /// look like four one-person companies, which a linear radius would exaggerate to sixteen.
    @Test("Grows area with headcount, within its clamp")
    func radiusGrowsAndClamps() throws {
        let one = BubblePacking.radius(headcount: 1)
        let four = BubblePacking.radius(headcount: 4)
        let huge = BubblePacking.radius(headcount: 5000)

        #expect(one == BubblePacking.minRadius)
        #expect(four > one)
        #expect(huge == BubblePacking.maxRadius)
        // An empty group is still drawable rather than collapsing to a point.
        #expect(BubblePacking.radius(headcount: 0) == BubblePacking.minRadius)

        // Area tracks headcount more faithfully than radius does.
        let areaRatio = (four * four) / (one * one)
        #expect(areaRatio > four / one)
    }

    /// Reproducibility is the whole point of packing rather than simulating: "Acme is the big
    /// one in the middle" has to stay true between launches, and so does its colour.
    @Test("Packs identically when rebuilt")
    func packingIsDeterministic() throws {
        let input = groups([3, 1, 4, 4], unaffiliated: 2)
        let first = BubblePacking(groups: input, in: pane)
        let second = BubblePacking(groups: input, in: pane)

        #expect(first.bubbles.map(\.id) == second.bubbles.map(\.id))
        #expect(first.bubbles.map(\.center) == second.bubbles.map(\.center))
        #expect(first.bubbles.map(\.radius) == second.bubbles.map(\.radius))
        #expect(first.bubbles.map(\.color) == second.bubbles.map(\.color))
    }

    /// Hue comes from the store's order, not the packing's, so a company keeps its colour
    /// whether or not it happens to be the largest — the bubbles and the ring you click
    /// through to must agree.
    @Test("Takes each hue from the store's order, not the packing's")
    func hueFollowsStoreOrder() throws {
        // Group 0 is the smallest, so packing reorders it to the back — its hue must not move
        // with it.
        let packing = BubblePacking(groups: groups([1, 9]), in: pane)
        let first = try #require(packing.bubbles.first { $0.id == "org-0" })
        let second = try #require(packing.bubbles.first { $0.id == "org-1" })

        #expect(first.color == Theme.clusterColor(at: 0))
        #expect(second.color == Theme.clusterColor(at: 1))
    }

    @Test("Cycles hues when a vault outgrows the palette")
    func paletteCycles() throws {
        let count = Theme.clusterPalette.count
        let packing = BubblePacking(
            groups: groups(Array(repeating: 1, count: count + 2)), in: pane)

        #expect(packing.bubbles.count == count + 2)
        #expect(Theme.clusterColor(at: count) == Theme.clusterColor(at: 0))
    }

    @Test("Resolves a point to the bubble containing it")
    func hitTesting() throws {
        let packing = BubblePacking(groups: groups([4, 4]), in: pane)
        let first = try #require(packing.bubbles.first)

        #expect(packing.bubble(at: first.center)?.id == first.id)
        // Just inside the rim hits; outside every circle misses.
        let justInside = CGPoint(x: first.center.x + first.radius - 1, y: first.center.y)
        #expect(packing.bubble(at: justInside)?.id == first.id)
        #expect(packing.bubble(at: .zero) == nil)
    }

    @Test("Centres a lone company instead of pushing it aside")
    func singleGroupIsCentred() throws {
        let packing = BubblePacking(groups: groups([4]), in: pane)
        let only = try #require(packing.bubbles.first)

        #expect(packing.bubbles.count == 1)
        #expect(abs(only.center.x - pane.width / 2) < 0.001)
        #expect(abs(only.center.y - pane.height / 2) < 0.001)
    }

    /// A single company must not be blown up to fill the window — the scale is there to fit a
    /// crowd into a narrow pane, not to make one circle look like a headcount it isn't.
    @Test("Caps how far a small packing is scaled up")
    func upscaleIsCapped() throws {
        let packing = BubblePacking(groups: groups([1]), in: CGSize(width: 2000, height: 2000))
        let only = try #require(packing.bubbles.first)

        #expect(only.radius <= BubblePacking.minRadius * BubblePacking.maxUpscale + 0.001)
    }

    @Test("Handles an empty vault without crashing")
    func emptyInput() throws {
        #expect(BubblePacking(groups: [], in: pane).bubbles.isEmpty)
    }

    /// The smallest bubble has to be able to hold what the view draws in it: a logo at the floor,
    /// the headcount, and up to two lines of name. If it can't, `minimumScaleFactor` shrinks the
    /// count — and a company shown with a smaller number reads as having fewer people in it.
    @Test("Leaves the smallest bubble room for a logo and its text")
    func smallestBubbleFitsItsContents() throws {
        let logo = max(
            BubblePacking.minRadius * OrganizationBubblesView.logoShare,
            OrganizationBubblesView.logoFloor)
        // The label column is inscribed in the circle, so this is the height available to it.
        let available = BubblePacking.minRadius * 2

        // 22pt count + two 11pt caption lines, at the line heights AppKit gives them, plus the
        // gap under the logo.
        let text: CGFloat = 27 + 14 * 2 + Theme.Spacing.xs
        #expect(logo + text <= available)
    }
}
