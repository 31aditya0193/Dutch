/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

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

    /// Generates off the main actor.
    ///
    /// `generate(from:)` is a few milliseconds of CIFilter encoding and
    /// rasterisation. Being `nonisolated async`, this runs on the cooperative
    /// pool rather than the caller's actor, so the share sheet's spinner keeps
    /// animating while the code is built.
    ///
    /// - Parameter url: The share URL to encode, or `nil` if iCloud hasn't
    ///   produced one yet.
    static func image(for url: URL?) async -> UIImage? {
        guard let string = url?.absoluteString else { return nil }
        return generate(from: string)
    }
}
