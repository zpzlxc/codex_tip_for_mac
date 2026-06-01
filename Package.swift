// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexHelper",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexHelper", targets: ["CodexHelper"])
    ],
    targets: [
        .executableTarget(
            name: "CodexHelper",
            path: "Sources/CodexHelper",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Security")
            ]
        )
    ]
)
