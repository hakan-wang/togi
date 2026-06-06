// swift-tools-version: 5.9
import PackageDescription

// Bogi — native macOS AI accountability coach + life data bank.
// Spec:  docs/superpowers/specs/2026-06-06-bogi-datalayer-design.md
// Plan:  docs/superpowers/plans/2026-06-06-bogi-full-product-implementation-plan.md
//
// Local-first: SQLite (GRDB) is the only user-data store. The backend is a
// stateless AWS proxy. Google Calendar uses raw ASWebAuthenticationSession PKCE
// (no GoogleSignIn SDK) so no client secret ships and tokens stay in the Keychain.
let package = Package(
    name: "Bogi",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Bogi", targets: ["BogiApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.2.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/jkrukowski/SQLiteVec.git", from: "0.0.13"),
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "BogiApp",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "SQLiteVec", package: "SQLiteVec"),
                .product(name: "Supabase", package: "supabase-swift"),
            ]
        ),
        .testTarget(
            name: "BogiAppTests",
            dependencies: ["BogiApp"]
        ),
    ]
)
