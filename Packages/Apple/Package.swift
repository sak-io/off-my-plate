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
        .library(name: "OMPShare", targets: ["OMPShare"]),
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
        // The Share Extension's logic and screen (S-40, ADR 0011, task T26). Links only OMPDomain
        // and OMPUI: never OMPServices, OMPData or OMPFeatures, so the extension cannot reach
        // planning, approval, the household or the store.
        .target(
            name: "OMPShare",
            dependencies: [
                "OMPUI",
                .product(name: "OMPDomain", package: "Core"),
            ]
        ),
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
            name: "OMPCaptureTests",
            dependencies: ["OMPCapture"]
        ),
        .testTarget(
            name: "OMPUITests",
            dependencies: ["OMPUI"]
        ),
        .testTarget(
            name: "OMPShareTests",
            dependencies: [
                "OMPShare",
                .product(name: "OMPDomain", package: "Core"),
            ]
        ),
        .testTarget(
            name: "OMPFeaturesTests",
            dependencies: [
                "OMPFeatures",
                "OMPCapture",
                .product(name: "OMPDomain", package: "Core"),
                .product(name: "OMPServices", package: "Core"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
