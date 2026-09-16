// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PythonUpdater",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PythonUpdater", targets: ["PythonUpdater"])
    ],
    targets: [
        .executableTarget(name: "PythonUpdater")
    ]
)