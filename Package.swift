// swift-tools-version: 6.0
// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import PackageDescription

let package = Package(
    name: "Mantle",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "Mantle",
            path: "Sources/Mantle",
            exclude: [
                "Resources/Info.plist",
                "Resources/Mantle.entitlements",
                "Resources/Mantle.icns",
                "Resources/Mantle.iconset",
                "Resources/Credits.rtf",
            ],
            resources: [
                .copy("Resources/exiftool"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        // Tier 1: fast, in-memory sanity checks. No exiftool, no image
        // decode, no real files. Run after every code-complete:
        //   ./scripts/test-tier1.sh
        .testTarget(
            name: "Tier1Tests",
            dependencies: ["Mantle"],
            path: "Tests/Tier1Tests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        // Tier 2: thorough integration checks against real files, the
        // bundled ExifTool, and ImageIO. Slower; run before a release:
        //   ./scripts/test-tier2.sh   (runs tier 1 + tier 2)
        .testTarget(
            name: "Tier2Tests",
            dependencies: ["Mantle"],
            path: "Tests/Tier2Tests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
