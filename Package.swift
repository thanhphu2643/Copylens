// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Copylens",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(name: "CTextCore"),
        .executableTarget(name: "Copylens", dependencies: ["CTextCore"]),
    ]
)
