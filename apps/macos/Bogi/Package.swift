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
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
    ],
    targets: [
        .executableTarget(
            name: "BogiApp",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
            // mascot.png is bundled straight into the .app's Contents/Resources by
            // Packaging/build-app.sh and loaded via Bundle.main. It is deliberately NOT an
            // SPM resource: the generated Bundle.module accessor only searches the app root
            // and the build machine's .build dir, so it fatalError'd on every other Mac.
        ),
        .testTarget(
            name: "BogiAppTests",
            dependencies: ["BogiApp"]
        )
    ]
)
