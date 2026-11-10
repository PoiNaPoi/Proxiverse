// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Reqnivo",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Reqnivo", targets: ["Reqnivo"])],
    targets: [
        .executableTarget(name: "Reqnivo", resources: [.copy("Resources/bridge.py"), .copy("Resources/install-certificate.dex"), .copy("Resources/Reqnivo.icns")]),
        .testTarget(name: "ReqnivoTests", dependencies: ["Reqnivo"])
    ]
)
