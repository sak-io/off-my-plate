// swift-tools-version: 6.0
import PackageDescription
let sentryURL = "https://github.com/getsentry/sentry-cocoa"
let package = Package(
    name: "Apple",
    dependencies: [
        .package(path: "../Core"),
        .package(url: sentryURL, from: "8.0.0"),
        .package(url: #"https://github.com/onevcat/Kingfisher"#, from: "8.0.0"),
        .package(id: registryID, from: "1.0.0"),
        .package(
            url:
                "https://example.com/x.git", from: "1.0.0"),
    ],
    targets: []
)
