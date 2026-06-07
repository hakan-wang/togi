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
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.0"),
        // Self-update for Developer-ID (non-App-Store) distribution. Sparkle ships as a
        // binary XCFramework; build-app.sh embeds + signs it into Contents/Frameworks.
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "BogiApp",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            // In the assembled .app, build-app.sh embeds Sparkle.framework in
            // Contents/Frameworks. Add that rpath so the binary (in Contents/MacOS) resolves
            // @rpath/Sparkle.framework there. The default @loader_path rpath still covers the
            // SwiftPM `.build` layout for dev/test runs.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "BogiAppTests",
            dependencies: ["BogiApp"]
        )
    ]
)
