// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NextMenus",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "NextMenus",
            targets: ["NextMenus"]
        )
    ],
    targets: [
        .executableTarget(
            name: "NextMenus",
            path: ".",
            exclude: [
                "README.md",
                "Info.plist"
            ],
            sources: [
                "NextMenusApp.swift",
                "AppDelegate.swift",
                "ApplicationObserver.swift",
                "MenuExtractor.swift",
                "MenuWindowController.swift",
                "SubmenuWindowController.swift",
                "NonActivatingWindow.swift",
                "HoverTableView.swift",
                "CenteredLabel.swift"
            ]
        )
    ]
)
