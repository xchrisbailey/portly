// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Portly",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PortlyCore", targets: ["PortlyCore"]),
        .executable(name: "Portly", targets: ["Portly"]),
    ],
    targets: [
        .target(name: "PortlyCore"),
        .executableTarget(name: "Portly", dependencies: ["PortlyCore"]),
        .testTarget(
            name: "PortlyCoreTests",
            dependencies: ["PortlyCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
