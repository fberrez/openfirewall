// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenFirewall",
    platforms: [.macOS(.v14)],
    products: [.library(name: "FirewallCore", targets: ["FirewallCore"])],
    targets: [
        .target(name: "FirewallCore", path: "Sources/Core"),
        .testTarget(name: "FirewallCoreTests", dependencies: ["FirewallCore"], path: "Tests/CoreTests")
    ],
    swiftLanguageModes: [.v5]
)
