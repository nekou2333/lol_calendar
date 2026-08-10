// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "LoLCalendar",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(name: "LoLCalendar"),
        .testTarget(name: "LoLCalendarTests", dependencies: ["LoLCalendar"])
    ],
    swiftLanguageModes: [.v6]
)
