import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Renders the Dutch app icon as flat vector artwork at 1024x1024.
// Geometry is transcribed from AppIcon.icon/Assets/*.svg and the layer
// placement in AppIcon.icon/icon.json, so the shapes match the Icon
// Composer original exactly — only the glass rendering is dropped.

let canvas: CGFloat = 1024

// Render in sRGB, not Display P3, even though icon.json specifies display-p3.
// A P3 asset makes the catalog compile *two* renditions of every image — an
// 8-bit sRGB one and a 16-bit extended-sRGB one — which more than doubles the
// icon's cost in Assets.car. The gamut difference is invisible at icon size;
// 1.8 MB is not.
let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

/// A display-p3 colour from icon.json, converted into sRGB for output.
func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    let source = CGColor(colorSpace: p3, components: [r, g, b, a])!
    return source.converted(to: srgb, intent: .relativeColorimetric, options: nil) ?? source
}

let blue = c(0.38431, 0.64706, 1.00000)
let mint = c(0.25882, 0.94510, 0.74510)

// MARK: - Shapes

/// ring.svg — two concentric circles in a 684x684 box, even-odd filled.
/// The SVG beziers are exact circle approximations (kappa 0.5523).
func ringPath() -> CGPath {
    let p = CGMutablePath()
    p.addEllipse(in: CGRect(x: 0, y: 0, width: 684, height: 684))
    p.addEllipse(in: CGRect(x: 78, y: 78, width: 528, height: 528))
    return p
}

/// share-large.svg — 293x421 box. Bulges right, straight closing edge on the left.
func shareLargePath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0.089996, y: 18.209961))
    p.addCurve(to: CGPoint(x: 222.698975, y: 57.065552),
               control1: CGPoint(x: 75.530975, y: -13.268677),
               control2: CGPoint(x: 162.382996, y: 1.891052))
    p.addCurve(to: CGPoint(x: 281.181946, y: 275.341248),
               control1: CGPoint(x: 283.014954, y: 112.240112),
               control2: CGPoint(x: 305.832336, y: 197.401489))
    p.addCurve(to: CGPoint(x: 107.820007, y: 420.289978),
               control1: CGPoint(x: 256.531494, y: 353.280945),
               control2: CGPoint(x: 188.893433, y: 409.833496))
    p.closeSubpath()
    return p
}

/// share-small.svg — 196x384 box. Bulges left, straight closing edge on the right.
func shareSmallPath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 91.399994, y: 2.089966))
    p.addCurve(to: CGPoint(x: 9.170349, y: 228.347534),
               control1: CGPoint(x: 19.191132, y: 52.753906),
               control2: CGPoint(x: -13.659424, y: 143.143311))
    p.addCurve(to: CGPoint(x: 193.51001, y: 383.179993),
               control1: CGPoint(x: 32.000122, y: 313.551758),
               control2: CGPoint(x: 105.643433, y: 375.406982))
    p.closeSubpath()
    return p
}

// MARK: - Placement
// Each layer is centred on the canvas at its natural size, then translated
// by icon.json's translation-in-points. SVG y grows downward.

struct Layer {
    let path: CGPath
    let size: CGSize
    let dx: CGFloat
    let dy: CGFloat

    /// Transform mapping the layer's local SVG coordinates into canvas space.
    func transform() -> CGAffineTransform {
        let ox = (canvas - size.width) / 2 + dx
        let oy = (canvas - size.height) / 2 + dy
        return CGAffineTransform(translationX: ox, y: oy)
    }

    func placed() -> CGPath {
        var t = transform()
        return path.copy(using: &t)!
    }
}

let ring = Layer(path: ringPath(), size: CGSize(width: 684, height: 684), dx: 0, dy: 0)
let large = Layer(path: shareLargePath(), size: CGSize(width: 293, height: 421),
                  dx: 63.76153952833806, dy: -0.6504140317074416)
let small = Layer(path: shareSmallPath(), size: CGSize(width: 196, height: 384),
                  dx: -118.26003697166198, dy: 25.34375)

// MARK: - Rendering

enum Variant: String {
    case light, dark, tinted
}

func render(_ variant: Variant, to url: URL) {
    // The light/any variant must be fully opaque. The dark and tinted variants
    // carry alpha: iOS composites them over a system-supplied background
    // gradient, so baking our own in would double up.
    let opaque = (variant == .light)
    let alphaInfo: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    let ctx = CGContext(data: nil, width: Int(canvas), height: Int(canvas),
                        bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                        bitmapInfo: alphaInfo.rawValue)!

    // Flip to SVG-style top-left origin with y growing downward.
    ctx.translateBy(x: 0, y: canvas)
    ctx.scaleBy(x: 1, y: -1)

    if opaque {
        // Full-bleed square; the system applies the rounded mask.
        // The gradient runs strictly vertically so every scanline is a single
        // repeated colour. A diagonal gradient makes all 1024 rows unique and
        // costs roughly 3x as much in the compiled asset catalog.
        let bg = CGGradient(colorsSpace: srgb,
                            colors: [c(1.0, 1.0, 1.0), c(0.925, 0.929, 0.945)] as CFArray,
                            locations: [0, 1])!
        ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 0),
                               end: CGPoint(x: 0, y: canvas), options: [])
    }

    // Ring — linear gradient blue to mint, running strictly top to bottom.
    //
    // icon.json sweeps this diagonally, and that orientation is the single
    // most expensive thing in the whole app. It is the same trap as the
    // background gradient above, on the element that actually dominates: a
    // diagonal sweep gives every pixel of the ring a unique value, so the row
    // filters the PNG and asset-catalog encoders rely on have nothing to
    // predict. Measured across the three variants, diagonal costs 392 KB and
    // vertical 179 KB — and the dark variant proves where the money goes, at
    // 164 KB with no background in it at all.
    //
    // Vertical is why the ring is drawn with a gradient at all rather than
    // flat. Keep both endpoints on the same x.
    ctx.saveGState()
    ctx.addPath(ring.placed())
    ctx.clip(using: .evenOdd)
    let t = ring.transform()
    let gStart = CGPoint(x: 342, y: 0).applying(t)
    let gStop = CGPoint(x: 342, y: 684).applying(t)
    let ringColors: [CGColor]
    switch variant {
    case .light, .dark: ringColors = [blue, mint]
    case .tinted:       ringColors = [c(0.62, 0.62, 0.62), c(0.82, 0.82, 0.82)]
    }
    let rg = CGGradient(colorsSpace: srgb, colors: ringColors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(rg, start: gStart, end: gStop,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // The two halves of the split circle.
    let largeColor: CGColor
    let smallColor: CGColor
    switch variant {
    case .light, .dark: largeColor = blue; smallColor = mint
    case .tinted:       largeColor = c(1.0, 1.0, 1.0); smallColor = c(0.55, 0.55, 0.55)
    }

    ctx.setFillColor(largeColor)
    ctx.addPath(large.placed())
    ctx.fillPath()

    ctx.setFillColor(smallColor)
    ctx.addPath(small.placed())
    ctx.fillPath()

    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
for v in [Variant.light, .dark, .tinted] {
    let url = outDir.appendingPathComponent("AppIcon-\(v.rawValue).png")
    render(v, to: url)
    print("wrote \(url.lastPathComponent)")
}
