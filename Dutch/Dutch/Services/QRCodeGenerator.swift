import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Renders QR codes for CloudKit share links.
enum QRCodeGenerator {
    private static let context = CIContext()

    /// Generates a crisp QR code image for the given text.
    ///
    /// The result is explicitly rasterised to a `CGImage`. A `CIImage`-backed
    /// `UIImage` carries no pixels until something draws it, and SwiftUI's
    /// `Image` frequently renders it blank.
    ///
    /// - Parameters:
    ///   - string: Payload to encode — for Dutch this is a CloudKit share URL.
    ///   - scale: Pixel multiplier applied to the generator's native output.
    /// - Returns: A square QR code image, or `nil` if encoding fails.
    static func generate(from string: String, scale: CGFloat = 12) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        // Share URLs are long, and this code gets scanned off a screen at an
        // angle more often than not, so favour error correction over density.
        filter.correctionLevel = "Q"

        guard let output = filter.outputImage else { return nil }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}
