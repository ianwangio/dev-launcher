import Foundation

/// 解析本机 `gh` 的绝对路径。
///
/// 顺序：登录 shell 的 `command -v gh`（过 `ExecutablePathFilter`）→ 三个常见安装位置。
/// 全落空就返回 nil，调用方据此把候选项置灰并写明"未找到 gh"（shape.md 2.1）。
public struct GhPathResolver: Sendable {
    public static let fallbackPaths = [
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
        NSString(string: "~/.local/bin/gh").expandingTildeInPath,
    ]

    private let runner: any CommandRunner
    private let fileSystem: any FileSystem
    private let loginShell: String

    public init(runner: any CommandRunner, fileSystem: any FileSystem, loginShell: String) {
        self.runner = runner
        self.fileSystem = fileSystem
        self.loginShell = loginShell
    }

    public func resolve() -> String? {
        if let fromShell = resolveViaLoginShell() { return fromShell }

        for path in Self.fallbackPaths where fileSystem.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private func resolveViaLoginShell() -> String? {
        guard
            let result = try? runner.run(
                executable: loginShell,
                arguments: ["-ilc", "command -v gh"],
                environment: nil,
                timeoutSeconds: 20
            ),
            result.exitCode == 0
        else { return nil }

        guard let path = ExecutablePathFilter.absolutePath(named: "gh", inShellOutput: result.stdout) else {
            return nil
        }
        guard fileSystem.isExecutableFile(atPath: path) else { return nil }
        return path
    }
}
