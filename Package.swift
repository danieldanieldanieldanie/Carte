// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Carte",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "CarteCore", targets: ["CarteCore"]),
        .library(name: "CarteFeature", targets: ["CarteFeature"])
    ],
    targets: [
        .target(name: "CarteCore", path: "Sources/CarteCore"),
        .target(name: "CarteFeature", dependencies: ["CarteCore"], path: "Sources/CarteFeature"),
        .testTarget(name: "CarteCoreTests", dependencies: ["CarteCore", "CarteFeature"], path: "Tests/CarteCoreTests")
    ]
)
