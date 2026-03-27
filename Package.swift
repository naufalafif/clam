// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clam",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "ClamLib",
            path: "Sources/Clam"
        ),
        .executableTarget(
            name: "Clam",
            dependencies: ["ClamLib"],
            path: "Sources/ClamEntry",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Info.plist",
                ]),
            ]
        ),
        .testTarget(
            name: "ClamTests",
            dependencies: ["ClamLib"]
        ),
    ]
)
