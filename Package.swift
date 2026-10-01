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
            exclude: [
                "CloudKitSyncHealthTests.swift",
                "LetterLibraryFilteringTests.swift",
                "LetterDeletionCoreDataTests.swift",
                "PersistenceStoreBookkeepingTests.swift",
                // Regression coverage for the app target's connection-state
                // mapping. It needs `@testable import LettersToMy`, which
                // `swift test` cannot resolve (the app target is not part of
                // this package), so it runs under the Xcode `LettersToMyTests`
                // target alongside the other four app-module files. Without
                // this exclusion `swift test` fails with "unable to resolve
                // module dependency: 'LettersToMy'".
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