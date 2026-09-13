import DevLauncherCore
import Foundation
import Testing

/// 唯一一条真实调用本机环境的测试。默认跳过 —— 断网或没装 gh 时不会红（decisions.md D12）。
///
/// 开启：`DEVLAUNCHER_INTEGRATION=1 swift test`
///
/// 保留它的理由是前作的教训：全是替身测试的套件会一路绿到交付，然后在真机上三个功能全废。
var integrationEnabled: Bool {
    ProcessInfo.processInfo.environment["DEVLAUNCHER_INTEGRATION"] == "1"
}

@Test("集成 · 本机的 gh 能被解析成绝对路径", .enabled(if: integrationEnabled))
func integration_resolvesRealGh() {
    // 这里刻意用真实实现，所以本文件是 B7 唯一的例外。
    let resolver = GhPathResolver(
        runner: RealCommandRunner(),
        fileSystem: RealFileSystem(),
        loginShell: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    )
    let path = resolver.resolve()
    #expect(path != nil, "本机解析不到 gh")
    #expect(path?.hasPrefix("/") == true, "解析出来的不是绝对路径：\(path ?? "nil")")
}

@Test("集成 · 本机 gh 能读取当前账号的真实仓库", .enabled(if: integrationEnabled))
func integration_readsRealRepositories() async throws {
    let fileSystem = RealFileSystem()
    let runner = RealCommandRunner()
    let cachePath = NSTemporaryDirectory() + "devlauncher-integration-repositories.json"
    defer { try? FileManager.default.removeItem(atPath: cachePath) }
    let provider = GitHubRepositoryProvider(
        runner: runner,
        fileSystem: fileSystem,
        clock: RealClock(),
        loginShell: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
        cachePath: cachePath
    )
    let snapshot = try await provider.repositories(policy: .reloadIgnoringCache)
    #expect(snapshot.accounts.isEmpty == false, "gh 没有返回已登录账号")
    #expect(snapshot.repositories.isEmpty == false, "gh 没有返回可访问仓库")
    #expect(snapshot.repositories.allSatisfy { $0.nameWithOwner.contains("/") })
    #expect(
        snapshot.repositories.contains { $0.latestPullRequestNumber != nil },
        "真实仓库没有返回任何最新 PR 编号"
    )
}

/// 集成测试专用的真实实现。App target 的 adapter 不能在这里复用 ——
/// 测试只依赖 Core，依赖 App 会让 target 依赖图长出第二条边。
private struct RealFileSystem: FileSystem {
    func fileExists(atPath path: String) -> Bool { FileManager.default.fileExists(atPath: path) }
    func isDirectory(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
    func isExecutableFile(atPath path: String) -> Bool { FileManager.default.isExecutableFile(atPath: path) }
    func read(atPath path: String) throws -> Data { try Data(contentsOf: URL(fileURLWithPath: path)) }
    func write(_ data: Data, toPath path: String) throws { try data.write(to: URL(fileURLWithPath: path)) }
    func createDirectory(atPath path: String) throws {
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: true)
    }
}

private struct RealCommandRunner: CommandRunner {
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String]?,
        timeoutSeconds: Double
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardInput = FileHandle.nullDevice

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        try process.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return CommandResult(
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }
}

private struct RealClock: Clock {
    var now: Date { Date() }
}
