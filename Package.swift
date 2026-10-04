// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VolumeControl",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "VolumeControl", targets: ["VolumeControl"])
    ],
    targets: [
        .executableTarget(
            name: "VolumeControl",
            path: "Sources/VolumeControl"
        ),
        .testTarget(
            name: "VolumeControlTests",
            dependencies: ["VolumeControl"],
            path: "Tests/VolumeControlTests"
        )
    ]
)
