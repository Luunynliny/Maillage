import Foundation
import SwiftUI
import Testing

@testable import MaillageCore

private let pane = CGSize(width: 900, height: 700)

private func person(_ id: EntityID, name: String? = nil, placeholder: Bool = false) -> Person {
    Person(
        id: id, firstname: placeholder ? nil : (name ?? id), placeholder: placeholder,
        descriptor: placeholder ? name : nil)
}

private func layout(
    subject: Person = person("me"),
    neighbours: [Person] = [],
    spokes: [EgoSpoke],
    employers: [EntityID: Int] = [:]
) -> EgoLayout {
    var index: [EntityID: Person] = [:]
    for neighbour in neighbours { index[neighbour.id] = neighbour }
    return EgoLayout(
        subject: subject, neighbours: index, spokes: spokes, in: pane,
        employer: { employers[$0] })
}

@Suite("Ego layout")
struct EgoLayoutTests {
    @Test("Centres the subject and rings the neighbours")
    func subjectIsCentred() throws {
        let result = layout(
            neighbours: [person("a"), person("b")],
            spokes: [
                EgoSpoke(neighbour: "a", label: "manager of", isOutbound: true),
                EgoSpoke(neighbour: "b", label: "works with", isOutbound: false),
            ])
        let subject = try #require(result.node(id: "me"))

        #expect(subject.center == result.center)
        #expect(subject.radius > EgoLayout.neighbourRadius)
        for id in ["a", "b"] {
            let node = try #require(result.node(id: id))
            #expect(abs(node.center.distance(to: result.center) - result.radius) < 0.001)
        }
    }

    /// One dot means one person, however many relations reach them — a neighbour drawn twice
    /// would double-count the network.
    @Test("Gives a person one node however many relations reach them")
    func neighboursAreDeduplicated() throws {
        let result = layout(
            neighbours: [person("a")],
            spokes: [
                EgoSpoke(neighbour: "a", label: "manager of", isOutbound: true),
                EgoSpoke(neighbour: "a", label: "friend of", isOutbound: true),
                EgoSpoke(neighbour: "a", label: "reports to", isOutbound: false),
            ])

        // One node for them, plus the subject.
        #expect(result.nodes.count == 2)
        // But every relation is still drawn and still labelled.
        #expect(result.spokes.count == 3)
        #expect(result.labels.count == 3)
    }

    /// A mutual pair is the interesting case, and two arrows on one line would read as a single
    /// ambiguous link — so the two curves have to bow to opposite sides.
    @Test("Bows a mutual pair's two edges apart")
    func mutualPairIsDrawnTwice() throws {
        let outbound = EgoSpoke(neighbour: "a", label: "manager of", isOutbound: true)
        let inbound = EgoSpoke(neighbour: "a", label: "reports to", isOutbound: false)
        let result = layout(neighbours: [person("a")], spokes: [outbound, inbound])
        let node = try #require(result.node(id: "a"))

        let straight = CGPoint(
            x: (result.center.x + node.center.x) / 2, y: (result.center.y + node.center.y) / 2)
        let first = result.control(for: outbound, from: result.center, to: node.center)
        let second = result.control(for: inbound, from: result.center, to: node.center)

        #expect(first != second)
        // On opposite sides of the straight chord, not merely offset by different amounts.
        #expect(first.distance(to: straight) > 1)
        #expect(second.distance(to: straight) > 1)
        #expect(first.distance(to: second) > first.distance(to: straight))
    }

    /// Nothing to disambiguate a lone relation from, so it stays straight — a bow for its own
    /// sake would suggest a second edge that isn't there.
    @Test("Leaves a lone relation straight")
    func lonelySpokeIsStraight() throws {
        let spoke = EgoSpoke(neighbour: "a", label: "knows", isOutbound: true)
        let result = layout(neighbours: [person("a")], spokes: [spoke])
        let node = try #require(result.node(id: "a"))

        let control = result.control(for: spoke, from: result.center, to: node.center)
        let midpoint = CGPoint(
            x: (result.center.x + node.center.x) / 2, y: (result.center.y + node.center.y) / 2)
        #expect(control.distance(to: midpoint) < 0.001)
    }

    /// Colleagues sitting together *and* sharing a hue is the whole reason employer decides both
    /// the order and the colour from one number.
    @Test("Groups neighbours by employer, then by name")
    func orderedByEmployerThenName() throws {
        let result = layout(
            neighbours: [
                person("zoe", name: "Zoe"), person("adam", name: "Adam"),
                person("bea", name: "Bea"), person("loner", name: "Loner"),
            ],
            spokes: [
                EgoSpoke(neighbour: "zoe", label: "knows", isOutbound: true),
                EgoSpoke(neighbour: "adam", label: "knows", isOutbound: true),
                EgoSpoke(neighbour: "bea", label: "knows", isOutbound: true),
                EgoSpoke(neighbour: "loner", label: "knows", isOutbound: true),
            ],
            // Zoe and Adam are colleagues; Bea works elsewhere; Loner has no employer.
            employers: ["zoe": 0, "adam": 0, "bea": 1])
        let ring = result.nodes.dropFirst().map(\.id)

        #expect(ring == ["adam", "zoe", "bea", "loner"])
        // Colleagues share a hue; the unemployed neighbour is grey, not a palette colour.
        #expect(result.node(id: "adam")?.color == result.node(id: "zoe")?.color)
        #expect(result.node(id: "bea")?.color != result.node(id: "adam")?.color)
        #expect(result.node(id: "loner")?.color == Theme.noClusterColor)
    }

    @Test("Draws a placeholder neighbour hollow, named by its descriptor")
    func placeholderNeighbour() throws {
        let result = layout(
            neighbours: [person("_cfo", name: "Northwind's CFO", placeholder: true)],
            spokes: [EgoSpoke(neighbour: "_cfo", label: "introduced by", isOutbound: false)])
        let node = try #require(result.node(id: "_cfo"))

        #expect(node.isHollow)
        #expect(node.label == "Northwind's CFO")
    }

    @Test("Draws a placeholder subject hollow too")
    func placeholderSubject() throws {
        let result = layout(
            subject: person("_cfo", name: "Northwind's CFO", placeholder: true),
            neighbours: [person("a")],
            spokes: [EgoSpoke(neighbour: "a", label: "knows", isOutbound: true)])

        #expect(result.node(id: "_cfo")?.isHollow == true)
    }

    /// A relation to a person no longer in the vault must not become a node with no name — the
    /// view filters dangling targets, and a name falling back to the raw id is the visible
    /// symptom if it ever stops.
    @Test("Falls back to the id when a neighbour is missing")
    func missingNeighbourStillLaysOut() throws {
        let result = layout(
            spokes: [EgoSpoke(neighbour: "ghost", label: "knew", isOutbound: true)])

        #expect(result.node(id: "ghost")?.label == "ghost")
        #expect(result.node(id: "ghost")?.isHollow == false)
    }

    @Test("Yields no neighbours when there are no relations")
    func noRelations() throws {
        let result = layout(spokes: [])

        // Only the subject, which is what drives the view's empty state.
        #expect(result.nodes.count == 1)
        #expect(result.labels.isEmpty)
    }

    @Test("Lays out identically when rebuilt")
    func layoutIsDeterministic() throws {
        let people = [person("a"), person("b"), person("c")]
        let spokes = [
            EgoSpoke(neighbour: "c", label: "knows", isOutbound: true),
            EgoSpoke(neighbour: "a", label: "manager of", isOutbound: false),
            EgoSpoke(neighbour: "b", label: "knows", isOutbound: true),
        ]
        let first = layout(neighbours: people, spokes: spokes, employers: ["a": 0, "b": 0])
        let second = layout(neighbours: people, spokes: spokes, employers: ["a": 0, "b": 0])

        #expect(first.nodes.map(\.id) == second.nodes.map(\.id))
        #expect(first.nodes.map(\.center) == second.nodes.map(\.center))
        #expect(first.labels.map(\.point) == second.labels.map(\.point))
    }

    /// The label is the payload — a relation with no words is just "connected", which the line
    /// already said — so every spoke must carry one.
    @Test("Labels every relation with its own words")
    func everySpokeIsLabelled() throws {
        let result = layout(
            neighbours: [person("a"), person("b")],
            spokes: [
                EgoSpoke(neighbour: "a", label: "manager of", isOutbound: true),
                EgoSpoke(neighbour: "b", label: "met at conference", isOutbound: false),
            ])

        #expect(result.labels.map(\.text) == ["manager of", "met at conference"])
        #expect(Set(result.labels.map(\.id)).count == 2)
    }

    /// Same reason as the org ring: a neighbour at three o'clock needs half their name's width
    /// clear of the rim, so the horizontal margin has to be the wider of the two — and, as
    /// there, it's capped at a share of the pane so a narrow one doesn't collapse the ring.
    @Test(
        "Leaves room for the names either side of the ring",
        arguments: [
            CGSize(width: 1400, height: 900),
            CGSize(width: 300, height: 700),
            CGSize(width: 900, height: 220),
        ])
    func ringFitsThePane(size: CGSize) throws {
        let result = EgoLayout(
            subject: person("me"), neighbours: ["a": person("a")],
            spokes: [EgoSpoke(neighbour: "a", label: "knows", isOutbound: true)],
            in: size, employer: { _ in nil })

        #expect(result.radius > 0)
        #expect(result.center == CGPoint(x: size.width / 2, y: size.height / 2))
        #expect(result.radius <= min(size.width, size.height) / 2)
        let allowance = min(
            size.width / 2 - min(EgoLayout.horizontalMargin, size.width * graphMarginShare),
            size.height / 2 - min(EgoLayout.verticalMargin, size.height * graphMarginShare))
        #expect(abs(result.radius - max(allowance, EgoLayout.subjectRadius * 3)) < 0.001)
        #expect(EgoLayout.horizontalMargin > EgoLayout.verticalMargin)
    }

    /// A narrow pane used to fall through to the floor, which stacked every neighbour and their
    /// name on top of the subject.
    @Test("Keeps the ring proportional on a narrow pane")
    func narrowPaneStillSpreadsTheRing() throws {
        let narrow = CGSize(width: 420, height: 380)
        let result = EgoLayout(
            subject: person("me"),
            neighbours: ["a": person("a"), "b": person("b")],
            spokes: [
                EgoSpoke(neighbour: "a", label: "knows", isOutbound: true),
                EgoSpoke(neighbour: "b", label: "knows", isOutbound: false),
            ],
            in: narrow, employer: { _ in nil })

        #expect(result.radius > EgoLayout.subjectRadius * 3)
        #expect(result.radius > min(narrow.width, narrow.height) / 2 * 0.6)
    }
}
