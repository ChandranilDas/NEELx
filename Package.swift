// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NEELx",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "NEELx", targets: ["NEELx"])
    ],
    targets: [
        .executableTarget(
            name: "NEELx",
            path: "source/NEELx",
            exclude: [
                "Assets.xcassets",
                "Resources",
                "Models",
                "Info.plist",
                "NEELx.entitlements",
                "neelxicon.icon"
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags([
                    "-default-isolation", "MainActor",
                    "-enable-upcoming-feature", "NonisolatedNonsendingByDefault"
                ])
            ]
        )
    ]
)
