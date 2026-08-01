// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MeetBar", targets: ["MeetBar"])
    ],
    targets: [
        .executableTarget(name: "MeetBar")
    ]
)
