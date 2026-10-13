// swift-tools-version: 6.0
// OffMyPlate Core: portable, Foundation-only domain logic (ADR 0004, ADR 0005).
// Builds and tests on Linux (CI: swift:6.2-noble) and on Apple platforms.
// Zero package dependencies: `scripts/lint-core-imports.sh` fails if one is added.
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "OMPDomain", targets: ["OMPDomain"]),
        .library(name: "OMPSafetyCheck", targets: ["OMPSafetyCheck"]),
        .library(name: "OMPRecipes", targets: ["OMPRecipes"]),
        .library(name: "OMPServices", targets: ["OMPServices"]),
    ],
    targets: [
        // Entities, units, safety gate, planner, plan lifecycle, pantry/shopping math,
        // learning, prompt scheduler and rule-based parsers.
        .target(name: "OMPDomain"),
        // The independent hard-rule plan validator (ADR 0007). Depends on the domain types only.
        .target(name: "OMPSafetyCheck", dependencies: ["OMPDomain"]),
        // Seed content (versioned JSON, ADR 0010), its loader and the seed validator.
        .target(name: "OMPRecipes", dependencies: ["OMPDomain"], resources: [.copy("Resources/seed")]),
        // Use cases, repository protocols and in-memory repositories.
        .target(name: "OMPServices", dependencies: ["OMPDomain", "OMPSafetyCheck", "OMPRecipes"]),
        // Prints the markdown seed sign-off sheet (ADR 0010, G1): `swift run seed-review-sheet [out.md]`.
        .executableTarget(name: "seed-review-sheet", dependencies: ["OMPRecipes"]),
        .testTarget(name: "OMPDomainTests", dependencies: ["OMPDomain"]),
        .testTarget(name: "OMPSafetyCheckTests", dependencies: ["OMPSafetyCheck", "OMPDomain", "OMPRecipes"]),
        .testTarget(name: "OMPRecipesTests", dependencies: ["OMPRecipes", "OMPDomain"]),
        .testTarget(name: "OMPServicesTests", dependencies: ["OMPServices", "OMPDomain"]),
        // The non-skippable safety suite (T12, plan section 8): CI runs it as its own step and
        // `scripts/lint-safety.sh` forbids disabling anything in it.
        .testTarget(name: "OMPSafetySuiteTests", dependencies: ["OMPDomain", "OMPSafetyCheck", "OMPRecipes"]),
    ],
    swiftLanguageModes: [.v6]
)
