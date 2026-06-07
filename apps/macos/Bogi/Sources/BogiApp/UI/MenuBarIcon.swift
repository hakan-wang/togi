import AppKit
import SwiftUI

/// Minimal line-art axolotl for the menu bar.
///
/// The full-colour 1024×1024 plush `mascot.png` reads as mud at 18pt, so the menu-bar label is a
/// hand-drawn vector mark reduced to the smallest set of shapes that still says "axolotl": a round
/// head, three plain gill strokes fanning each side, two dot eyes, and the little smile. No filled
/// leaf shapes, no flourishes — just the iconic silhouette.
///
/// It is drawn through `NSImage(size:flipped:drawingHandler:)`, so AppKit re-runs the path at the
/// exact pixel scale every time it paints — genuinely resolution-independent, like an SVG. Flagged
/// `isTemplate`, the system tints it for light/dark menus and inverts it while the menu is open,
/// matching every other native menu-bar item.
enum MenuBarIcon {

    /// Cached template image for the menu bar. The full-colour `mascot.png` (`BogiAsset.mascot`)
    /// stays in use for the larger, in-window mascot surfaces — this only replaces the 18pt label.
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            draw(in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Togi"
        return image
    }()

    // MARK: - Drawing

    /// All geometry is authored on a 24×24 grid (origin top-left, matching `flipped: true`) and
    /// scaled to whatever `rect` AppKit hands us.
    private static func draw(in rect: NSRect) {
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + x / 24 * rect.width,
                    y: rect.minY + y / 24 * rect.height)
        }
        let unit = rect.width / 24
        let lineWidth = max(1, 1.6 * unit)

        NSColor.black.setStroke()
        NSColor.black.setFill()

        // Head — a soft round face, the heart of the plush.
        let head = NSBezierPath(ovalIn: NSRect(x: rect.minX + 6 / 24 * rect.width,
                                               y: rect.minY + 6 / 24 * rect.height,
                                               width: 12 / 24 * rect.width,
                                               height: 12 / 24 * rect.height))
        head.lineWidth = lineWidth
        head.stroke()

        // Gills — three plain strokes fanning out each side, mirrored across the centre line.
        // Each tuple: where the stroke meets the head → its outer tip.
        let gills: [(base: (CGFloat, CGFloat), tip: (CGFloat, CGFloat))] = [
            (base: (7.3, 8.5), tip: (3.0, 5.0)),    // upper, swept up
            (base: (6.0, 12.0), tip: (1.2, 12.0)),  // middle, straight out
            (base: (7.3, 15.5), tip: (3.0, 19.0)),  // lower, swept down
        ]
        for gill in gills {
            for side in [CGFloat(1), CGFloat(-1)] {
                let base = mirror(gill.base, side: side)
                let tip = mirror(gill.tip, side: side)
                let stroke = NSBezierPath()
                stroke.move(to: p(base.0, base.1))
                stroke.line(to: p(tip.0, tip.1))
                stroke.lineWidth = lineWidth
                stroke.lineCapStyle = .round
                stroke.stroke()
            }
        }

        // Eyes — two dots.
        let eyeR = 1.05 * unit
        for cx in [CGFloat(9.8), CGFloat(14.2)] {
            let c = p(cx, 11.5)
            NSBezierPath(ovalIn: NSRect(x: c.x - eyeR, y: c.y - eyeR,
                                        width: eyeR * 2, height: eyeR * 2)).fill()
        }

        // Smile — a gentle downward bow.
        let smile = NSBezierPath()
        smile.move(to: p(10.2, 14.4))
        smile.curve(to: p(13.8, 14.4),
                    controlPoint1: p(11.3, 16.2),
                    controlPoint2: p(12.7, 16.2))
        smile.lineWidth = lineWidth
        smile.lineCapStyle = .round
        smile.stroke()
    }

    /// Mirror a grid point across the vertical centre line (x = 12) when `side` is -1.
    private static func mirror(_ point: (CGFloat, CGFloat), side: CGFloat) -> (CGFloat, CGFloat) {
        side > 0 ? point : (24 - point.0, point.1)
    }
}
