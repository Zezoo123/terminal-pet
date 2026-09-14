// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "terminal-pet",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "terminal-pet",
            path: "Sources/terminal-pet",
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ImageIO")]
        )
    ]
)
