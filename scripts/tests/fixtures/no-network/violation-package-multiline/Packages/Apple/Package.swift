// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Apple",
    dependencies: [
        .package(path: "../Core"),
        .package(
            name: "Sentry",
            url: "https://github.com/getsentry/sentry-cocoa",
            from: "8.0.0"
        ),
    ],
    targets: []
)
