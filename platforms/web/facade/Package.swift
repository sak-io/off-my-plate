// swift-tools-version: 6.0
// OffMyPlate web facade (W03, ADR 0016): the JSON-in/JSON-out door between the browser app and the
// Swift core. Depends on ../../../core by path only: zero third-party packages (ADR 0002,
// scripts/lint-no-network.sh). Native `swift test` runs on Linux and macOS; the wasm products are built
// with the Wasm SDK (.github/workflows/web-facade.yml).
import PackageDescription

let package = Package(
    name: "WebFacade",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "OMPWeb", targets: ["OMPWeb"]),
        // Reads JSON request lines on stdin, writes response lines on stdout (native and wasmtime).
        .executable(name: "omp-web-cli", targets: ["omp-web-cli"]),
        // The browser module (WASI reactor): omp_alloc / omp_free / omp_call / omp_result_ptr / omp_version.
        .executable(name: "omp-web-wasm", targets: ["OMPWebWasm"]),
    ],
    dependencies: [
        .package(path: "../../../core"),
    ],
    targets: [
        .target(
            name: "OMPWeb",
            dependencies: [
                .product(name: "OMPDomain", package: "core"),
                .product(name: "OMPSafetyCheck", package: "core"),
                .product(name: "OMPRecipes", package: "core"),
                .product(name: "OMPServices", package: "core"),
            ]
        ),
        .executableTarget(name: "omp-web-cli", dependencies: ["OMPWeb"]),
        .executableTarget(name: "OMPWebWasm", dependencies: ["OMPWeb"]),
        .testTarget(
            name: "OMPWebTests",
            dependencies: [
                "OMPWeb",
                .product(name: "OMPDomain", package: "core"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
