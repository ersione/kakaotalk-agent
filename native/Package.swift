// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KakaoTalkBridge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "kakaotalk-bridge", targets: ["KakaoTalkBridge"]),
        .library(name: "KakaoDBCore", targets: ["KakaoDBCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .systemLibrary(
            name: "CSQLCipher",
            pkgConfig: "sqlcipher",
            providers: [.brew(["sqlcipher"])]
        ),
        .target(
            name: "KakaoDBCore",
            dependencies: ["CSQLCipher"]
        ),
        .executableTarget(
            name: "VersionGenTool"
        ),
        .plugin(
            name: "VersionGenPlugin",
            capability: .buildTool(),
            dependencies: ["VersionGenTool"]
        ),
        .executableTarget(
            name: "KakaoTalkBridge",
            dependencies: [
                "KakaoDBCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/KakaoTalkBridge",
            plugins: [.plugin(name: "VersionGenPlugin")]
        ),
    ]
)
