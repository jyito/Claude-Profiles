import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// A small deterministic QR generator for the Remote sheet. `CIQRCodeGenerator`
/// produces a tiny pixel grid; we nearest-neighbour scale it up so the modules stay
/// crisp. Deterministic for a fixed input string (a fixed error-correction level →
/// a fixed module grid → a fixed bitmap), which keeps the Remote golden stable.
public enum QRCode {
    /// A QR `NSImage` for `string`, scaled to roughly `points` on a side, or nil if
    /// CoreImage can't produce one. Error correction "L" (densest payload for a short
    /// SSH command). The bitmap is rendered to an explicit sRGB CGImage so the PNG is
    /// byte-stable across runs.
    public static func image(for string: String, points: CGFloat = 160) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "L"
        guard let output = filter.outputImage else { return nil }

        let extent = output.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        // Integer scale so module edges land on pixel boundaries (no blur).
        let scale = max(1, (points / extent.width).rounded(.down))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        let side = CGFloat(cg.width)
        return NSImage(cgImage: cg, size: NSSize(width: side, height: side))
    }
}
