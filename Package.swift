// swift-tools-version: 6.0

// The Swift SDK (ADR 0034; docs/sdks/PLAN.md, N5): a workspace's feedback widget in an iOS app's sheet, a
// macOS app's sheet or a view of either, with the app's user signed in. A release copies this folder to the
// public repository that Swift Package Manager installs it from (N8).

import PackageDescription

let package = Package(
    name: "Swingback",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "Swingback", targets: ["Swingback"])
    ],
    targets: [
        .target(name: "Swingback", resources: [.process("PrivacyInfo.xcprivacy")]),
        .testTarget(name: "SwingbackTests", dependencies: ["Swingback"]),
    ]
)
