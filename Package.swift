// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MovieCut",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "MovieCutCore",
            targets: ["MovieCutCore"]
        )
    ],
    targets: [
        .target(
            name: "MovieCutCore",
            path: "Sources/MovieCutCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        ),
        .testTarget(
            name: "MovieCutCoreTests",
            dependencies: ["MovieCutCore"],
            path: "Tests/MovieCutCoreTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
