// Render the Togi app icon: the mascot centered on the brand sky gradient inside a macOS
// squircle, then emit an .icns. Dependency-free (AppKit/CoreGraphics + sips/iconutil).
//
//   swift Packaging/make-appicon.swift <mascot.png> <out.icns>
//
// Brand colors are kept in sync with Sources/BogiApp/UI/BogiTheme.swift (BogiGradient.sky).
import AppKit

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: make-appicon.swift <mascot.png> <out.icns>\n".utf8))
    exit(2)
}
let mascotPath = CommandLine.arguments[1]
let outIcns = CommandLine.arguments[2]

func rgb(_ hex: UInt) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

/// Draw the 1024×1024 master icon into a PNG at `url`.
func renderMaster(to url: URL) throws {
    let size: CGFloat = 1024
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let ctx = NSGraphicsContext(bitmapImageRep: rep)
    else { throw NSError(domain: "appicon", code: 1) }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    // macOS icon grid: the rounded square sits inside a transparent margin (~10%), with a
    // corner radius of ~0.2237× its side. This matches the proportions of stock app icons.
    let inset: CGFloat = 100
    let squircle = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = squircle.width * 0.2237

    // Sky gradient (BogiGradient.sky): blue at the top warming to cream at the bottom. CG's
    // origin is bottom-left, so the start point is the top edge.
    cg.saveGState()
    cg.addPath(CGPath(roundedRect: squircle, cornerWidth: radius, cornerHeight: radius, transform: nil))
    cg.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [rgb(0x94ccf3), rgb(0xb2defa), rgb(0xd4f0fe), rgb(0xf6f7e4), rgb(0xfff9e4)] as CFArray,
        locations: [0.0, 0.30, 0.56, 0.80, 1.0])!
    cg.drawLinearGradient(gradient,
                          start: CGPoint(x: size / 2, y: squircle.maxY),
                          end: CGPoint(x: size / 2, y: squircle.minY), options: [])
    cg.restoreGState()

    // Mascot centered inside the squircle with breathing room on every side.
    guard let mascot = NSImage(contentsOfFile: mascotPath),
          let tiff = mascot.tiffRepresentation,
          let mrep = NSBitmapImageRep(data: tiff),
          let mcg = mrep.cgImage
    else { throw NSError(domain: "appicon", code: 2) }
    let pad: CGFloat = 0.15                      // fraction of the squircle on each side
    let avail = squircle.width * (1 - 2 * pad)
    let mRect = CGRect(x: squircle.midX - avail / 2, y: squircle.midY - avail / 2,
                       width: avail, height: avail)
    cg.draw(mcg, in: mRect)

    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "appicon", code: 3)
    }
    try png.write(to: url)
}

// 1) Render the 1024 master.
let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("togi-appicon-master.png")
try renderMaster(to: tmp)

// 2) Build the .iconset (all required sizes) via sips, then pack with iconutil.
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Togi.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
func run(_ launch: String, _ args: [String]) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launch)
    p.arguments = args
    try p.run(); p.waitUntilExit()
    if p.terminationStatus != 0 { throw NSError(domain: "appicon", code: Int(p.terminationStatus)) }
}
for v in variants {
    let dst = iconset.appendingPathComponent("\(v.name).png").path
    try run("/usr/bin/sips", ["-z", "\(v.px)", "\(v.px)", tmp.path, "--out", dst])
}
try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", outIcns])
print("wrote \(outIcns)")
