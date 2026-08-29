import SwiftUI
import Testing

@testable import MaillageCore

private func node(center: CGPoint, radius: CGFloat) -> GraphNode {
    GraphNode(id: "n", center: center, radius: radius, color: .clear, label: "n")
}

@Suite("Graph geometry")
struct GraphGeometryTests {
    // MARK: ringRadius

    @Test("Shrinks the rim to leave room for margins, down to the floor")
    func ringRadiusRespectsMargins() throws {
        let radius = ringRadius(
            in: CGSize(width: 400, height: 400), horizontal: 60, vertical: 40, floor: 50)
        let expected: CGFloat = 400 / 2 - 60
        #expect(radius == expected)
    }

    @Test("Caps each margin at its share of the pane, so a narrow pane doesn't collapse")
    func ringRadiusCapsMarginOnNarrowPane() throws {
        // horizontal=200 would eat almost the whole half-width; graphMarginShare caps it.
        let radius = ringRadius(
            in: CGSize(width: 200, height: 400), horizontal: 200, vertical: 40, floor: 10)
        let cappedMargin: CGFloat = 200 * graphMarginShare
        let expected: CGFloat = 200 / 2 - cappedMargin
        #expect(radius == expected)
    }

    @Test("Never returns less than the floor")
    func ringRadiusHonorsFloor() throws {
        let radius = ringRadius(
            in: CGSize(width: 40, height: 40), horizontal: 60, vertical: 60, floor: 25)
        #expect(radius == 25)
    }

    // MARK: arrowhead

    @Test("Draws a triangle whose back corners straddle the tip symmetrically")
    func arrowheadIsSymmetricAroundApproachAxis() throws {
        let tip = CGPoint(x: 100, y: 100)
        // Approaching from directly below (larger y), so the head points straight up — the
        // apex sits at `tip`, the wider back corners trail below it.
        let path = arrowhead(at: tip, approaching: CGPoint(x: 100, y: 160))
        let box = path.boundingRect
        #expect(abs(box.midX - tip.x) < 0.001)
        #expect(abs(box.minY - tip.y) < 0.001)
        #expect(box.maxY > tip.y)
    }

    // MARK: trimmed(from:to:)

    @Test("Trims both ends to sit on each node's rim, not its centre")
    func trimmedTouchesRims() throws {
        let from = node(center: CGPoint(x: 0, y: 0), radius: 10)
        let to = node(center: CGPoint(x: 100, y: 0), radius: 20)
        let (start, end) = trimmed(from: from, to: to, gap: 2)

        #expect(abs(start.distance(to: from.center) - 12) < 0.001)
        #expect(abs(end.distance(to: to.center) - 22) < 0.001)
        // Both trimmed points still lie on the straight line between the two centres.
        #expect(abs(start.y) < 0.001)
        #expect(abs(end.y) < 0.001)
    }

    // MARK: CGPoint

    @Test("onCircle at angle 0 lands at the top, clockwise from there")
    func onCircleStartsAtTop() throws {
        let center = CGPoint(x: 50, y: 50)
        let top = CGPoint.onCircle(center: center, radius: 10, angle: 0)
        #expect(abs(top.x - 50) < 0.001)
        #expect(abs(top.y - 40) < 0.001)

        // A quarter turn clockwise from the top lands to the right.
        let right = CGPoint.onCircle(center: center, radius: 10, angle: .pi / 2)
        #expect(abs(right.x - 60) < 0.001)
        #expect(abs(right.y - 50) < 0.001)
    }

    @Test("distance(to:) is plain Euclidean distance")
    func distanceIsEuclidean() throws {
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 3, y: 4)
        #expect(a.distance(to: b) == 5)
    }
}
