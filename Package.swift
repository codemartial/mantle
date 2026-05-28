// swift-tools-version: 6.0
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
    ]
)
