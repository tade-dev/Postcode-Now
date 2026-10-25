// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PostcodeNowCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "PostcodeNowCore", targets: ["PostcodeNowCore"]),
    ],
    targets: [
        .target(name: "PostcodeNowCore"),
        .testTarget(
            name: "PostcodeNowCoreTests",
            dependencies: ["PostcodeNowCore"]
        ),
    ]
)
