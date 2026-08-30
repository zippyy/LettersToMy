// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LettersToMyCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LettersToMyCore", targets: ["LettersToMyCore"]),
        .executable(name: "selfhosted-check", targets: ["SelfHostedCheck"])
    ],
    targets: [
        .target(name: "LettersToMyCore"),
        .testTarget(
            name: "LettersToMyCoreTests",
            dependencies: ["LettersToMyCore"],
            exclude: [
                "CloudKitSyncHealthTests.swift",
                "LetterLibraryFilteringTests.swift"
            ]
        ),
        .executableTarget(
            name: "SelfHostedCheck",
            dependencies: ["LettersToMyCore"]
        )
    ]
)