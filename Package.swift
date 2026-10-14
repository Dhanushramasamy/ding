// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Ding",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Plays the character animations (Lottie JSON files in Characters/).
        .package(url: "https://github.com/airbnb/lottie-spm.git", from: "4.5.0")
    ],
    targets: [
        .executableTarget(
            name: "Ding",
            dependencies: [.product(name: "Lottie", package: "lottie-spm")],
            path: "Sources/Ding"
        )
    ]
)
