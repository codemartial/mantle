// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Metadater",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "Metadater",
            path: "Sources/Metadater",
            exclude: [
                "Resources/Info.plist",
                "Resources/Metadater.entitlements",
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
