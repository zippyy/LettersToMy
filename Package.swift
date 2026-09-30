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
        .executable(name: "selfhosted-check", targets: ["SelfHostedCheck"]),
        .executable(name: "backup-e2e", targets: ["BackupE2E"])
    ],
    targets: [
        .target(name: "LettersToMyCore"),
        .testTarget(
            name: "LettersToMyCoreTests",
            dependencies: ["LettersToMyCore"],
            // Files listed here are excluded from the SwiftPM test target
            // because they `@testable import LettersToMy` (the app module).
            // SwiftPM's LettersToMyCoreTests depends only on LettersToMyCore and
            // cannot see the app module, so `swift test` (the Core tests CI job)
            // fails to compile them. They still run under the Xcode
            // LettersToMyTests target, which links the app.
            exclude: [
                "CloudKitSyncHealthTests.swift",
                "LetterLibraryFilteringTests.swift",
                "LetterDeletionCoreDataTests.swift",
                "PersistenceStoreBookkeepingTests.swift",
                "SelfHostedConnectionStateTests.swift"
            ]
        ),
        .executableTarget(
            name: "SelfHostedCheck",
            dependencies: ["LettersToMyCore"]
        ),
        .executableTarget(
            name: "BackupE2E",
            dependencies: ["LettersToMyCore"]
        )
    ]
)