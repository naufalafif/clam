// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clam",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Clam",
            path: "Sources/Clam",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Info.plist",
                ]),
            ]
        ),
    ]
)
