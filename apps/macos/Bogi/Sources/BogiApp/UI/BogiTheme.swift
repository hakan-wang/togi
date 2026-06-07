import SwiftUI
import AppKit

/// Brand tokens from brand/togi-design-profile.json: dreamy pastel sky, Apple frosted
/// glass, sky-blue accent, the soft plush axolotl. Calm, honest, never corporate.
enum BogiColor {
    static let primary = Color(hex: 0x0a88cc)   // sky-blue accent
    static let ink = Color(hex: 0x15110d)       // warm near-black text
    static let muted = Color(hex: 0x5a5450)
    static let background = Color(hex: 0xecf7fe)
    static let mascotBlue = Color(hex: 0xa7cdd6)
}

enum BogiGradient {
    /// The dreamy sky: blue at the top warming to cream at the bottom.
    static let sky = LinearGradient(
        stops: [
            .init(color: Color(hex: 0x94ccf3), location: 0.0),
            .init(color: Color(hex: 0xb2defa), location: 0.30),
            .init(color: Color(hex: 0xd4f0fe), location: 0.56),
            .init(color: Color(hex: 0xf6f7e4), location: 0.80),
            .init(color: Color(hex: 0xfff9e4), location: 1.0),
        ],
        startPoint: .top, endPoint: .bottom
    )
}

/// The mascot IS the logo: the baby-blue plush axolotl. Loaded from the bundled asset,
/// with an SF Symbol fallback so the UI never breaks if the resource is missing.
enum BogiAsset {
    /// Locate the SwiftPM resource bundle by searching real, on-disk locations.
    ///
    /// We deliberately AVOID SwiftPM's generated `Bundle.module` accessor: for an executable
    /// wrapped into a `.app`, it only checks `Togi.app/Bogi_BogiApp.bundle` (the bundle root,
    /// where the bundle is NOT placed) and a hard-coded absolute dev build path — then calls
    /// `fatalError`. That dev path exists only on the build machine, so the packaged app
    /// crashed on launch for every other machine (DMG / /Applications / Gatekeeper
    /// translocation). This returns `nil` instead of crashing.
    static func locateResourceBundle(searchURLs: [URL],
                                     bundleName: String = "Bogi_BogiApp.bundle") -> Bundle? {
        for base in searchURLs {
            let url = base.appendingPathComponent(bundleName)
            if FileManager.default.fileExists(atPath: url.path), let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return nil
    }

    /// The bundle holding `mascot.png`. `build-app.sh` places `Bogi_BogiApp.bundle` in
    /// `Contents/Resources`; in dev (`swift run`/tests) it sits next to the executable.
    private static let resourceBundle: Bundle = {
        let candidates = [
            Bundle.main.resourceURL,                                   // Contents/Resources (packaged)
            Bundle.main.executableURL?.deletingLastPathComponent(),    // Contents/MacOS / dev build dir
            Bundle.main.bundleURL,                                     // .app root
        ].compactMap { $0 }
        return locateResourceBundle(searchURLs: candidates) ?? .main
    }()

    static let mascot: Image = {
        if let url = Bundle.main.url(forResource: "mascot", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return Image(nsImage: image)
        }
        return Image(systemName: "tortoise.fill")
    }()
}

extension Color {
    init(hex: UInt) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: 1)
    }
}

/// Gentle vertical bob (translateY 0 → -distance, ease-in-out, forever). Respects Reduce
/// Motion. Per the brand motion spec: "gentle vertical bob, 5s ease-in-out infinite."
struct BobModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lifted = false
    var distance: CGFloat = 9
    var duration: Double = 2.5

    func body(content: Content) -> some View {
        content
            .offset(y: lifted ? -distance : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                    lifted = true
                }
            }
    }
}

extension View {
    func bob(distance: CGFloat = 9, duration: Double = 2.5) -> some View {
        modifier(BobModifier(distance: distance, duration: duration))
    }
}
