// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MasterUI",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "MasterUI",
            dependencies: ["SwiftTerm"],
            path: "Sources/MasterUI",
            resources: [
                .copy("../../Resources/Info.plist"),
            ]
        ),
    ]
)
