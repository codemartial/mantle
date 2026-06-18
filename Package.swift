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
        .testTarget(
            name: "MantleTests",
            dependencies: ["Mantle"],
            path: "Tests/MantleTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
