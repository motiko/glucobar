// swift-tools-version: 6.0
import PackageDescription

// GlucoBarCore must build on Linux (see docs/adr/0003): no AppKit, SwiftUI,
// Security/Keychain, AVFoundation or CryptoKit imports in this package.
let package = Package(
    name: "GlucoBarCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GlucoBarCore", targets: ["GlucoBarCore"]),
    ],
    targets: [
        .target(name: "GlucoBarCore"),
        .testTarget(name: "GlucoBarCoreTests", dependencies: ["GlucoBarCore"]),
    ]
)
