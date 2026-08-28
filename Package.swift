// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PulseDock",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "PulseDock", targets: ["PulseDock"])],
    targets: [
        .executableTarget(
            name: "PulseDock",
            dependencies: ["TemperatureBridge"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Network")
            ]
        ),
        .target(
            name: "TemperatureBridge",
            path: "Sources/TemperatureBridge",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("Foundation")]
        ),
        .testTarget(name: "PulseDockTests", dependencies: ["PulseDock"])
    ]
)
