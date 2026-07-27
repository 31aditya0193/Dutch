// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DutchKit",
    platforms: [
        .iOS(.v17),
        // macOS is not a shipping target; it exists so `swift test` runs the
        // pure logic from the command line without booting a simulator.
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "DutchKit",
            targets: ["DutchKit"]
        ),
    ],
    targets: [
        .target(
            name: "DutchKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DutchKitTests",
            dependencies: ["DutchKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
