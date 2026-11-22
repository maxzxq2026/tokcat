// swift-tools-version: 6.0

// Tokcat native core. Layering follows RunCatNeo's LUCA architecture
// (UserInterface → Model → DataSource, one-way), adapted to macOS 13:
// no @Observable, ObservableObject throughout.
//
// DataSource:  Sendable value types + system-API dependency clients.
// Collector:   the usage-data layer ported from src-tauri (parsers, pricing,
//              tailer, quota) — imported only by Model's composition root.
// Model:       app logic (ports of src/lib/*.ts), services, stores.
// UserInterface: SwiftUI views, no logic.
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny")
]

let package = Package(
    name: "LocalPackage",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DataSource", targets: ["DataSource"]),
        .library(name: "Collector", targets: ["Collector"]),
        .library(name: "Model", targets: ["Model"]),
        .library(name: "UserInterface", targets: ["UserInterface"]),
        .executable(name: "tokcat-dump", targets: ["tokcat-dump"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .target(
            name: "DataSource",
            swiftSettings: swiftSettings
        ),
        // The usage-data layer ported from src-tauri: parsers, pricing,
        // aggregation, tailer, quota providers. Only Model's composition
        // root and the parity CLI import it.
        .target(
            name: "Collector",
            dependencies: ["DataSource"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "Model",
            dependencies: [
                "DataSource", "Collector",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [.copy("Resources/TrayFrames")],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "UserInterface",
            dependencies: ["DataSource", "Model"],
            resources: [
                .copy("Resources/AgentIcons"),
                .copy("Resources/tokcat-logo.png"),
            ],
            swiftSettings: swiftSettings
        ),
        // Parity CLI: dumps the collector output as deterministic JSON for
        // diffing against the Rust `usage_dump` bin (scripts/parity-check.sh).
        .executableTarget(
            name: "tokcat-dump",
            dependencies: ["Collector", "DataSource"],
            swiftSettings: swiftSettings
        ),
        // The menubar app's @main entry. Sources/tokcat-app/AppMain.swift is
        // a symlink to ../../Tokcat/TokcatApp.swift — the file stays where
        // XcodeGen's app target (native/project.yml) expects it; this target
        // only exists so scripts/build-local-app.sh can produce a runnable
        // Tokcat.app with the bare Command Line Tools, no Xcode required.
        .executableTarget(
            name: "tokcat",
            dependencies: ["Model", "UserInterface"],
            path: "Sources/tokcat-app",
            // The XcodeGen app target compiles TokcatApp.swift in language
            // mode 5 (SWIFT_VERSION "5.0"); match it or strict concurrency
            // rejects the MainActor hand-off around the panel factory.
            swiftSettings: swiftSettings + [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CollectorTests",
            dependencies: ["Collector"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ModelTests",
            dependencies: ["Model"],
            resources: [.copy("Resources/golden.json")],
            swiftSettings: swiftSettings
        ),
        // View geometry that would otherwise only be checkable by eye: width
        // budgets from the same AppKit font metrics the views draw, plus an
        // ImageRenderer pass that measures the drawn ink of a real view.
        .testTarget(
            name: "UserInterfaceTests",
            dependencies: ["UserInterface"],
            swiftSettings: swiftSettings
        ),
    ]
)
