import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageImportError: Error, LocalizedError {
    case unreadable(URL)
    case conversionFailed(URL)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url):
            "\(url.lastPathComponent) isn't an image this Mac can read"
        case .conversionFailed(let url):
            "\(url.lastPathComponent) couldn't be converted to a square PNG"
        }
    }
}

/// Turns any image file into the one format the vault stores logos in.
///
/// Every logo becomes a 512×512 PNG, whatever was dropped in, so nothing downstream has to
/// cope with a 4000px HEIC or a 3:1 wordmark: a view can draw a logo knowing its shape and
/// weight in advance, and the vault stays a folder of files a person can browse.
///
/// **PNG** because it is the only lossless format with alpha that macOS can *write* — the
/// writable set is png, heic and heics — and logos are usually transparent. **512** because the
/// largest place one is drawn is an organization bubble at up to ``BubblePacking/maxRadius``
/// (150pt radius, so 300pt across), which wants 600px on a Retina display; 512 is the nearest
/// power of two and costs a few tens of kilobytes.
///
/// No dependency, and none needed. `NSImage` reads every type ImageIO knows — PNG, JPEG, HEIC,
/// WebP, AVIF, TIFF, GIF, BMP, ICO — *and* SVG, which a bare `CGImageSource` does not. An image
/// library would be a larger surface for strictly less coverage.
public enum ImageSquarer {
    /// Side of the stored square, in pixels.
    public static let side = 512

    /// Reads `url`, centre-crops it to a square, and returns it as 512×512 PNG data.
    ///
    /// Centre-crop rather than fit: a logo fills its circle with no transparent bars, which is
    /// what makes a row of avatars read as one column. The cost is that a very wide wordmark
    /// loses its ends — this is the one function to change if that ever matters more.
    public static func squarePNG(contentsOf url: URL) throws -> Data {
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0
        else {
            throw ImageImportError.unreadable(url)
        }
        guard let data = squarePNG(from: image) else {
            throw ImageImportError.conversionFailed(url)
        }
        return data
    }

    /// The conversion itself, split out so tests can drive it from an in-memory image.
    public static func squarePNG(from image: NSImage) -> Data? {
        guard
            let target = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: side,
                pixelsHigh: side,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .calibratedRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0)
        else { return nil }
        // Set explicitly: without it the rep is 512pt at 1× on one machine and 256pt at 2× on
        // another, and `draw` would fill only a quarter of the pixels.
        target.size = CGSize(width: side, height: side)

        guard let context = NSGraphicsContext(bitmapImageRep: target) else { return nil }
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.current = previous }
        // The scaling is the whole job, so ask for the good sampler rather than the fast one.
        context.imageInterpolation = .high

        // The largest centred square of the source. Cropping here, in one `draw`, rather than
        // scaling and then trimming: two passes would resample twice and soften the result.
        let sourceSide = min(image.size.width, image.size.height)
        let source = CGRect(
            x: (image.size.width - sourceSide) / 2,
            y: (image.size.height - sourceSide) / 2,
            width: sourceSide,
            height: sourceSide)

        image.draw(
            in: CGRect(x: 0, y: 0, width: side, height: side),
            from: source,
            operation: .copy,
            fraction: 1)
        context.flushGraphics()

        return target.representation(using: .png, properties: [:])
    }

    /// The file types the import panel should offer.
    ///
    /// Asked of the system rather than listed by hand, so the panel accepts exactly what
    /// ``squarePNG(contentsOf:)`` can actually read and the two cannot drift apart. SVG is
    /// appended because `NSImage` handles it while ImageIO does not report it.
    public static var readableTypes: [UTType] {
        var types = (CGImageSourceCopyTypeIdentifiers() as? [String] ?? [])
            .compactMap(UTType.init)
        if let svg = UTType("public.svg-image"), !types.contains(svg) {
            types.append(svg)
        }
        return types
    }
}
