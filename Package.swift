// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Carte",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "CarteCore", targets: ["CarteCore"])
    ],
    targets: [
        .target(name: "CarteCore", path: "Sources/CarteCore")
    ]
)
