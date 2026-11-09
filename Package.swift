// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Proxiverse",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Proxiverse", targets: ["Proxiverse"])],
    targets: [
        .executableTarget(name: "Proxiverse", resources: [.copy("Resources/bridge.py"), .copy("Resources/install-certificate.dex"), .copy("Resources/Proxiverse.icns")]),
        .testTarget(name: "ProxiverseTests", dependencies: ["Proxiverse"])
    ]
)
