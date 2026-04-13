// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Respect",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Respect",
            path: "Sources/Respect"
        )
    ]
)
