// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DevLauncher",
    platforms: [.macOS(.v26)],
    targets: [
        // 纯逻辑。不 import SwiftUI / AppKit，不直接制造副作用。
        // 边界由 Tests/DevLauncherCoreTests/BoundaryTests.swift 的 B2 / B3 守。
        .target(name: "DevLauncherCore", path: "Sources/DevLauncherCore", exclude: ["README.md"]),

        // 界面与系统交互。依赖方向只有 App → Core；反向会被 SwiftPM 判为循环依赖（B1）。
        .executableTarget(
            name: "DevLauncherApp",
            dependencies: ["DevLauncherCore"],
            path: "Sources/DevLauncherApp",
            exclude: ["README.md"]
        ),

        .testTarget(
            name: "DevLauncherCoreTests",
            dependencies: ["DevLauncherCore"],
            path: "Tests/DevLauncherCoreTests",
            // 金样本由 BoundaryTests 用 #filePath 直接读，不走 bundle 资源。
            exclude: ["Fixtures/default-rules.json"]
        ),
    ]
)
