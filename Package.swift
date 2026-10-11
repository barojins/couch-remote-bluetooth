// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RemoteProtocol",
    products: [.library(name: "RemoteProtocol", targets: ["RemoteProtocol"])],
    targets: [
        .target(name: "RemoteProtocol", path: "Shared"),
        .testTarget(name: "RemoteProtocolTests", dependencies: ["RemoteProtocol"], path: "Tests")
    ]
)
