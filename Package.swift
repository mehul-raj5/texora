// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Texora",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Texora",
            path: "Sources/Texora"
        ),
        .testTarget(
            name: "TexoraTests",
            dependencies: ["Texora"],
            path: "Tests/TexoraTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
