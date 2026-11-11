// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GridironTickerPro",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .executableTarget(
            name: "GridironTickerPro",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/GridironTickerPro"
        )
    ]
)
