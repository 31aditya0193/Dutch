// swift-tools-version: 6.0

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

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
            swiftSettings: [
                .swiftLanguageMode(.v6),
                // Matches the app target's `-Osize`. SwiftPM has no supported
                // setting for the optimisation level, so this is the only way
                // to keep the package from being the one part of the binary
                // still compiled for speed — worth 16 KB of a 1.2 MB app.
                //
                // `unsafeFlags` is safe here in the way that actually matters:
                // it is rejected only for packages resolved as a *versioned*
                // dependency, and DutchKit is a local path reference inside
                // this workspace. Release only, so `swift test` is untouched.
                .unsafeFlags(["-Osize"], .when(configuration: .release)),
            ]
        ),
        .testTarget(
            name: "DutchKitTests",
            dependencies: ["DutchKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
