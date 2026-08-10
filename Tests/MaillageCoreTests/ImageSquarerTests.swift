import AppKit
import Foundation
import Testing

@testable import MaillageCore

/// A solid rectangle, so a test can assert on its dimensions.
private func solid(width: Int, height: Int, color: NSColor) -> NSImage {
    let image = NSImage(size: CGSize(width: width, height: height))
    image.lockFocus()
    color.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    image.unlockFocus()
    return image
}

/// Three vertical bands, so a test can tell which part of a source survived the crop.
private func banded(
    width: Int, height: Int, left: NSColor, middle: NSColor, right: NSColor
) -> NSImage {
    let image = NSImage(size: CGSize(width: width, height: height))
    image.lockFocus()
    let third = CGFloat(width) / 3
    left.setFill()
    NSRect(x: 0, y: 0, width: third, height: CGFloat(height)).fill()
    middle.setFill()
    NSRect(x: third, y: 0, width: third, height: CGFloat(height)).fill()
    right.setFill()
    NSRect(x: third * 2, y: 0, width: third, height: CGFloat(height)).fill()
    image.unlockFocus()
    return image
}

/// Fixtures are generated in-process rather than committed, so no binary files enter the repo
/// and the sizes under test are visible in the test itself.
@Suite("Image squarer")
struct ImageSquarerTests {
    @Test("A wide source comes out square at the stored size")
    func squaresAWideSource() throws {
        let data = try #require(
            ImageSquarer.squarePNG(from: solid(width: 800, height: 200, color: .red)))
        let result = try #require(NSBitmapImageRep(data: data))

        #expect(result.pixelsWide == ImageSquarer.side)
        #expect(result.pixelsHigh == ImageSquarer.side)
    }

    @Test("A tall source comes out square at the stored size")
    func squaresATallSource() throws {
        let data = try #require(
            ImageSquarer.squarePNG(from: solid(width: 120, height: 900, color: .blue)))
        let result = try #require(NSBitmapImageRep(data: data))

        #expect(result.pixelsWide == ImageSquarer.side)
        #expect(result.pixelsHigh == ImageSquarer.side)
    }

    /// A source *smaller* than 512 is scaled up rather than left padded — otherwise a 64px
    /// favicon would land in a corner of a mostly-transparent square.
    @Test("A small source is scaled up to fill the square")
    func upscalesASmallSource() throws {
        let data = try #require(
            ImageSquarer.squarePNG(from: solid(width: 32, height: 32, color: .green)))
        let result = try #require(NSBitmapImageRep(data: data))

        #expect(result.pixelsWide == ImageSquarer.side)
        #expect(result.pixelsHigh == ImageSquarer.side)
        // Corner as well as centre: a source pinned at its natural size would leave this
        // transparent.
        let corner = try #require(result.colorAt(x: 4, y: 4))
        #expect(corner.alphaComponent > 0.9)
    }

    @Test("Colour survives the conversion")
    func keepsItsColour() throws {
        let data = try #require(
            ImageSquarer.squarePNG(from: solid(width: 300, height: 300, color: .red)))
        let result = try #require(NSBitmapImageRep(data: data))

        let sample = try #require(result.colorAt(x: ImageSquarer.side / 2, y: ImageSquarer.side / 2))
        let converted = try #require(sample.usingColorSpace(.sRGB))
        #expect(converted.redComponent > 0.85)
        #expect(converted.greenComponent < 0.2)
        #expect(converted.blueComponent < 0.2)
    }

    /// The decision the whole conversion rests on, made assertable: a 900×300 source keeps its
    /// middle third and loses both ends. This is what "a wide wordmark loses its ends" means in
    /// pixels, and it is the one behaviour to change if that trade-off is ever revisited.
    @Test("Squaring keeps the centre and discards the ends")
    func cropsToTheCentre() throws {
        let source = banded(
            width: 900, height: 300, left: .red, middle: .green, right: .blue)
        let data = try #require(ImageSquarer.squarePNG(from: source))
        let result = try #require(NSBitmapImageRep(data: data))

        // Sampled at three points across the middle row. All three should be the source's
        // centre band, since a 300pt-tall crop of a 900pt-wide image is its middle third.
        for x in [8, ImageSquarer.side / 2, ImageSquarer.side - 8] {
            let sample = try #require(result.colorAt(x: x, y: ImageSquarer.side / 2))
            let converted = try #require(sample.usingColorSpace(.sRGB))
            #expect(converted.greenComponent > 0.85, "x=\(x) should be the centre band")
            #expect(converted.redComponent < 0.2, "x=\(x) kept the left band")
            #expect(converted.blueComponent < 0.2, "x=\(x) kept the right band")
        }
    }

    @Test("A file that isn't an image throws rather than writing nonsense")
    func rejectsANonImage() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("maillage-not-an-image-\(UUID().uuidString).png")
        try Data("this is not a PNG".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ImageImportError.self) {
            try ImageSquarer.squarePNG(contentsOf: url)
        }
    }

    @Test("A missing file throws")
    func rejectsAMissingFile() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("maillage-absent-\(UUID().uuidString).png")

        #expect(throws: ImageImportError.self) {
            try ImageSquarer.squarePNG(contentsOf: url)
        }
    }

    /// The claim the "no new dependency" decision rests on: the formats a logo is likely to
    /// arrive in are all readable by the system. If this ever fails, that decision needs
    /// revisiting rather than working around.
    @Test("The panel offers the formats a logo actually arrives in")
    func offersTheUsualFormats() {
        let identifiers = Set(ImageSquarer.readableTypes.map(\.identifier))

        for expected in [
            "public.png", "public.jpeg", "public.heic", "org.webmproject.webp",
            "public.tiff", "com.compuserve.gif", "public.svg-image",
        ] {
            #expect(identifiers.contains(expected), "\(expected) should be readable")
        }
    }
}
