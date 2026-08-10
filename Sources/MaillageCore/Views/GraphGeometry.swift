import SwiftUI

/// The pieces the centre pane's graphs draw themselves out of.
///
/// All of it is pure geometry over `CGPoint`: given the same inputs it returns the same
/// points, every launch. That is the property the views are chosen for — neither the bubbles
/// nor the ego graph is a simulation, so nothing here settles, drifts, or needs a frame
/// clock — and it's also what lets the layouts be unit-tested without a window.
///
/// Kept out of the view files rather than inlined, because a circle placed and hit-tested by
/// the same arithmetic in both graphs can't read as clickable in one and dead in the other —
/// a bug the user experiences as "clicking works here but not there".

// MARK: - Node

/// A laid-out circle: where it goes, what it's called, and what selecting it means.
///
/// Deliberately not tied to `Person`. What a layout hands the renderer is position and
/// appearance, already resolved — so a view draws circles without knowing what they stand for,
/// and a layout can be tested without a vault.
struct GraphNode: Identifiable, Equatable {
    let id: EntityID
    let center: CGPoint
    let radius: CGFloat
    /// The employer's hue, from ``Theme/clusterColor(at:)``.
    let color: Color
    let label: String
    /// A placeholder person, drawn as an outline. Grey would collide with "no employer",
    /// and an outline reads as "not yet known" in any colour.
    let isHollow: Bool

    init(
        id: EntityID,
        center: CGPoint,
        radius: CGFloat,
        color: Color,
        label: String,
        isHollow: Bool = false
    ) {
        self.id = id
        self.center = center
        self.radius = radius
        self.color = color
        self.label = label
        self.isHollow = isHollow
    }
}

// MARK: - Hit testing

/// How far outside a node's edge still counts as a hit, in points.
///
/// A drawn node is around 14pt across, which is smaller than a pointer can reasonably be
/// asked to land on. Padding the target keeps a click that is visually on the dot from
/// reading as a click on empty canvas.
let graphHitSlop: CGFloat = 8

// MARK: - Rings

/// The most of a pane's half-width or half-height a name is allowed to reserve.
///
/// A margin is what a name *wants*; this is what the pane can afford to give it.
let graphMarginShare: CGFloat = 0.18

/// The rim radius for a ring drawn in `size`, leaving room for the names around it.
///
/// `horizontal` and `vertical` are the room a name needs at a comfortable width — but they're
/// caps, not promises. On a narrow pane a fixed reserve is most of the half-width, so
/// subtracting it outright collapses the ring to `floor`: every dot and every name piled into
/// the middle, which is far less readable than a name reaching close to the pane's edge. Each
/// margin is therefore also limited to ``graphMarginShare`` of the dimension it eats into, so
/// the ring stays proportional to whatever pane it's handed.
func ringRadius(in size: CGSize, horizontal: CGFloat, vertical: CGFloat, floor: CGFloat)
    -> CGFloat
{
    let horizontal = min(horizontal, size.width * graphMarginShare)
    let vertical = min(vertical, size.height * graphMarginShare)
    return max(min(size.width / 2 - horizontal, size.height / 2 - vertical), floor)
}

// MARK: - Edges

/// The arrowhead for a one-way relation, as a filled triangle sitting at `tip`.
///
/// Relations are one-way by project rule, so direction is information the picture has to
/// carry. Two head-to-head arrows on one pair say "each declared the other", which a single
/// line could not.
///
/// `approach` is the point the line arrives *from*, which is a curve's control point rather
/// than its other endpoint — otherwise the head points along the chord while the line
/// arrives at an angle.
func arrowhead(
    at tip: CGPoint, approaching approach: CGPoint, size: CGFloat = 7,
    spread: Angle = .degrees(26)
) -> Path {
    let angle = atan2(tip.y - approach.y, tip.x - approach.x)
    let left = angle + spread.radians
    let right = angle - spread.radians

    return Path { path in
        path.move(to: tip)
        path.addLine(
            to: CGPoint(x: tip.x - size * cos(left), y: tip.y - size * sin(left)))
        path.addLine(
            to: CGPoint(x: tip.x - size * cos(right), y: tip.y - size * sin(right)))
        path.closeSubpath()
    }
}

/// Where an edge should start and stop so it touches a node's rim rather than its centre.
///
/// Drawn centre-to-centre, a line disappears under both dots and an arrowhead lands in the
/// middle of the target instead of pointing at it.
func trimmed(from: GraphNode, to: GraphNode, gap: CGFloat = 2) -> (start: CGPoint, end: CGPoint) {
    let angle = atan2(to.center.y - from.center.y, to.center.x - from.center.x)
    let startOffset = from.radius + gap
    let endOffset = to.radius + gap
    return (
        CGPoint(
            x: from.center.x + cos(angle) * startOffset,
            y: from.center.y + sin(angle) * startOffset),
        CGPoint(
            x: to.center.x - cos(angle) * endOffset,
            y: to.center.y - sin(angle) * endOffset)
    )
}

// MARK: - Points

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// The point `radius` away at `angle`, measured the way the layouts do: clockwise from
    /// straight up, so arc 0 starts at the top and reads left to right like text.
    static func onCircle(center: CGPoint, radius: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + radius * sin(angle),
            y: center.y - radius * cos(angle))
    }
}
