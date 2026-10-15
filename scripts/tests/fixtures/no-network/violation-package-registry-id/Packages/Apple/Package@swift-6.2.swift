// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "Apple",
    dependencies: [.package(id: "mona.LinkedList", exact: "1.0.0")],
    targets: [.binaryTarget(name: "Blob", url: "https://example.com/blob.zip", checksum: "00")]
)
