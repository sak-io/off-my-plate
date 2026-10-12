// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "Core",
    dependencies: [
        .package(
            id: "apple.swift-crypto", from: "3.0.0"),
    ],
    targets: [.target(name: "OMPDomain")]
)
