import AppKit
import ImageIO
import UniformTypeIdentifiers

// Re-layout a full-bleed app icon onto the macOS icon grid: scale the
// artwork into the ~824px content box of a 1024px canvas, add the standard
// soft drop shadow, and leave transparent margins around it. The upstream
// icon.icns is drawn edge-to-edge, which renders as a hard square in
// Launchpad/Dock next to properly gridded system icons.
//
// Usage: swift scripts/fix-app-icon.swift <in.png> <out.png>
// Pipeline: fix the 1024 master, then sips-downscale the iconset sizes and
// iconutil -c icns (see the commit that touched native/Tokcat/icon.icns).

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: fix-app-icon.swift <in.png> <out.png>\n".data(using: .utf8)!)
    exit(2)
}
let srcURL = URL(fileURLWithPath: args[1])
let dstURL = URL(fileURLWithPath: args[2])

guard
    let src = CGImageSourceCreateWithURL(srcURL as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
else {
    FileHandle.standardError.write("cannot read \(args[1])\n".data(using: .utf8)!)
    exit(1)
}

let canvas: CGFloat = 1024
let content: CGFloat = 824  // Apple's grid: the shape occupies ~80.5% of the canvas
let margin = CGFloat(canvas - content) / 2

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8,
    bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high

// The source artwork carries a baked-in white keyline around its squircle
// and a hard full-bleed edge. Drop both: fill the standard rounded shape
// with the background charcoal (so any sliver at the clipped corners stays
// invisible), then draw the source zoomed in enough that the keyline falls
// outside the clip — the cat and the background texture come through whole.
let shape = CGRect(x: margin, y: margin, width: content, height: content)
let radius = CGFloat(content) * 0.2245  // macOS squircle-like corner curve
let zoom: CGFloat = 30                  // source pixels hidden per side

// Shadow first, from the filled shape, before any clipping.
ctx.saveGState()
// CGContext is y-up: a negative height offset draws the shadow below.
ctx.setShadow(
    offset: CGSize(width: 0, height: -7), blur: 16,
    color: NSColor.black.withAlphaComponent(0.25).cgColor)
ctx.setFillColor(NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.16, alpha: 1).cgColor)
ctx.addPath(CGPath(roundedRect: shape, cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(CGPath(roundedRect: shape, cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.clip()
ctx.draw(
    image,
    in: CGRect(
        x: margin - zoom, y: margin - zoom,
        width: content + 2 * zoom, height: content + 2 * zoom))
ctx.restoreGState()
guard let out = ctx.makeImage() else { exit(1) }

guard
    let dest = CGImageDestinationCreateWithURL(
        dstURL as CFURL, UTType.png.identifier as CFString, 1, nil)
else { exit(1) }
CGImageDestinationAddImage(dest, out, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
print("wrote \(dstURL.path)")
