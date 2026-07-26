// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LettersToMyCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LettersToMyCore", targets: ["LettersToMyCore"])
    ],
    targets: [
        .target(name: "LettersToMyCore"),
        .testTarget(
            name: "LettersToMyCoreTests",
            dependencies: ["LettersToMyCore"]
        )
    ]
)
