// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VolumeControl",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VolumeControl", targets: ["VolumeControl"])
    ],
    targets: [
        .target(name: "VolumeControlDSP", path: "Sources/VolumeControlDSP", publicHeadersPath: "include"),
        .executableTarget(
            name: "VolumeControl",
            dependencies: ["VolumeControlDSP"],
            path: "Sources/VolumeControl"
        ),
        .testTarget(
            name: "VolumeControlTests",
            dependencies: ["VolumeControl", "VolumeControlDSP"],
            path: "Tests/VolumeControlTests"
        )
    ]
)
