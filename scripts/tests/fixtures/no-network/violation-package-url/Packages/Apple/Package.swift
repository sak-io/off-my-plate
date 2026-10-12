// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Apple",
    dependencies: [
        .package(path: "../Core"),
        .package( url: "https://github.com/firebase/firebase-ios-sdk", from: "11.0.0"),
    ],
    targets: []
)
