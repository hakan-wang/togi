// swift-tools-version: 5.9
import PackageDescription

// Phase 0 keeps dependencies minimal (GRDB only) so the scaffold resolves and builds
// quickly. Later phases add: SQLiteVec (Phase 2), supabase-swift (Phase 3),
// KeyboardShortcuts + Sparkle (Phases 6/8), Google PKCE (Phase 4).
let package = Package(
    name: "Bogi",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Bogi", targets: ["BogiApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
        // GFM markdown rendering (tables + lists) in chat bubbles. SwiftUI's built-in
        // Text(markdown:) can't render tables/lists, so we use MarkdownUI.
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.0")
    ],
    targets: [
        .executableTarget(
            name: "BogiApp",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ]
            // mascot.png is NOT declared as an SPM resource: the generated Bundle.module
            // accessor only searches the .app root + a hardcoded build path, so it traps
            // at launch inside a packaged app. Instead build-app.sh stages mascot.png into
            // Contents/Resources and BogiAsset loads it via Bundle.main. See BogiTheme.swift.
        ),
        .testTarget(
            name: "BogiAppTests",
            dependencies: ["BogiApp"]
        )
    ]
)
