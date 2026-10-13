// swift-tools-version: 6.0
// OffMyPlate Apple package: the Apple-only modules (ADR 0004). iOS 18 / macOS 15.
// Depends on ../Core by path only: zero third-party packages (ADR 0002, lint-no-network.sh).
// `swift test` runs on macOS (CI: apple-macos.yml); it does not build on Linux.
import PackageDescription

let package = Package(
    name: "Apple",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "OMPData", targets: ["OMPData"]),
        .library(name: "OMPCapture", targets: ["OMPCapture"]),
        .library(name: "OMPUI", targets: ["OMPUI"]),
        .library(name: "OMPFeatures", targets: ["OMPFeatures"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        // SwiftData persistence and the repository implementations (ADR 0003; task T20).
        .target(
            name: "OMPData",
            dependencies: [
                .product(name: "OMPDomain", package: "Core"),
                .product(name: "OMPServices", package: "Core"),
            ]
        ),
        // Apple capture adapters, Speech only in v1 (ADR 0012; task T30).
        .target(
            name: "OMPCapture",
            dependencies: [
                .product(name: "OMPDomain", package: "Core"),
            ]
        ),
        // Design system: tokens and shared SwiftUI components (task T21). No Core dependency,
        // so the share extension can link it without reaching services.
        .target(name: "OMPUI"),
        // Screens and view models; the app target stays a thin composition root.
        .target(
            name: "OMPFeatures",
            dependencies: [
                "OMPUI",
                "OMPCapture",
                .product(name: "OMPDomain", package: "Core"),
                .product(name: "OMPServices", package: "Core"),
            ]
        ),
        .testTarget(
            name: "OMPDataTests",
            dependencies: [
                "OMPData",
                .product(name: "OMPDomain", package: "Core"),
                .product(name: "OMPServices", package: "Core"),
            ]
        ),
        .testTarget(
            name: "OMPUITests",
            dependencies: ["OMPUI"]
        ),
        .testTarget(
            name: "OMPFeaturesTests",
            dependencies: [
                "OMPFeatures",
                .product(name: "OMPDomain", package: "Core"),
                .product(name: "OMPServices", package: "Core"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
