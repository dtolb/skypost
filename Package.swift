// swift-tools-version: 6.2
// BlueSkyTemplates v2 — SPM workspace.
//
// Module layout per NEXT_STEPS_MAY_20_2026.md §5. The iOS app target itself
// is *not* defined here — SwiftPM cannot produce an iOS app bundle. The app
// target lives in App/BlueSkyTemplates.xcodeproj (generated from
// App/project.yml via xcodegen) and depends on these library products.

import PackageDescription

let package = Package(
    name: "BlueSkyTemplates",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .macOS(.v15),
    ],
    products: [
        .library(name: "BlueSkyTemplatesApp", targets: ["BlueSkyTemplatesApp"]),
        .library(name: "DesignSystem",       targets: ["DesignSystem"]),
        .library(name: "Auth",               targets: ["Auth"]),
        .library(name: "Bluesky",            targets: ["Bluesky"]),
        .library(name: "Models",             targets: ["Models"]),
        .library(name: "Templates",          targets: ["Templates"]),
        .library(name: "Compose",            targets: ["Compose"]),
        .library(name: "AppLogging",         targets: ["AppLogging"]),
    ],
    dependencies: [
        // Pins per §8.1 and §9.
        .package(url: "https://github.com/MasterJ93/ATProtoKit.git",
                 "0.32.5"..<"0.33.0"),
        .package(url: "https://github.com/kean/Nuke.git",
                 "13.0.6"..<"14.0.0"),
        .package(url: "https://github.com/EmergeTools/Pow.git",
                 from: "1.0.6"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git",
                 "2.4.1"..<"3.0.0"),
    ],
    targets: [
        // ── Leaf modules ────────────────────────────────────────────────
        // Named AppLogging (not Logging) to avoid colliding with
        // swift-log's "Logging" target, which is in the transitive graph
        // via ATProtoKit.
        .target(name: "AppLogging"),

        .target(
            name: "Models",
            dependencies: []
        ),

        .target(
            name: "DesignSystem",
            dependencies: [
                .product(name: "Pow", package: "Pow"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "NukeUI", package: "Nuke"),
            ]
        ),

        // ── Bluesky module — the ONLY place that imports ATProtoKit. ───
        .target(
            name: "Bluesky",
            dependencies: [
                "AppLogging",
                "Models",
                .product(name: "ATProtoKit", package: "ATProtoKit"),
            ]
        ),

        // ── Auth — exposes AuthProvider protocol; AppPasswordAuth impl. ─
        .target(
            name: "Auth",
            dependencies: [
                "Bluesky",
                "AppLogging",
                "Models",
            ]
        ),

        // ── SwiftData models live in Templates per §5. ─────────────────
        .target(
            name: "Templates",
            dependencies: [
                "DesignSystem",
                "Models",
            ]
        ),

        .target(
            name: "Compose",
            dependencies: [
                "Auth",
                "Bluesky",
                "DesignSystem",
                "AppLogging",
                "Models",
                "Templates",
            ]
        ),

        // ── App composition root. ──────────────────────────────────────
        .target(
            name: "BlueSkyTemplatesApp",
            dependencies: [
                "Auth",
                "Bluesky",
                "Compose",
                "DesignSystem",
                "AppLogging",
                "Models",
                "Templates",
            ]
        ),

        // ── Tests — one sanity test per target. ────────────────────────
        .testTarget(
            name: "ComposeTests",
            dependencies: ["Compose"]
        ),
        .testTarget(
            name: "TemplatesTests",
            dependencies: ["Templates"]
        ),
        .testTarget(
            name: "AuthTests",
            dependencies: ["Auth"]
        ),
        .testTarget(
            name: "BlueskyTests",
            dependencies: ["Bluesky"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
