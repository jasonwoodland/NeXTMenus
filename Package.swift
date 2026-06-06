// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NeXTMenus",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "NeXTMenus",
            targets: ["NeXTMenus"]
        )
    ],
    targets: [
        .target(
            name: "NeXTMenusKit",
            path: "Sources/NeXTMenusKit"
        ),
        .executableTarget(
            name: "NeXTMenus",
            dependencies: ["NeXTMenusKit"],
            path: "Sources/NeXTMenus"
        ),
        .testTarget(
            name: "NeXTMenusKitTests",
            dependencies: ["NeXTMenusKit"],
            path: "Tests/NeXTMenusKitTests"
        ),
        .testTarget(
            name: "NeXTMenusTests",
            dependencies: ["NeXTMenus"],
            path: "Tests/NeXTMenusTests"
        )
    ]
)
