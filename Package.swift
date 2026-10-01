// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PlacodeCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "PlacodeCore", targets: ["PlacodeCore"]),
    ],
    targets: [
        .target(name: "PlacodeCore"),
        .testTarget(
            name: "PlacodeCoreTests",
            dependencies: ["PlacodeCore"]
        ),
    ]
)
