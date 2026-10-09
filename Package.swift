// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Marked",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-cmark", revision: "0c8947bbd58c491c54aae114aca40621cddc8357"),
    ],
    targets: [
        .target(
            name: "MarkedCore",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ]
        ),
        .executableTarget(name: "Marked", dependencies: ["MarkedCore"]),
        .testTarget(name: "MarkedCoreTests", dependencies: ["MarkedCore"]),
    ]
)
