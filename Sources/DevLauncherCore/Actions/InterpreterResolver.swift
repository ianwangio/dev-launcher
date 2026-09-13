import Foundation

/// 决定用哪个解释器跑一个脚本（decisions.md D6）。
///
/// 判定顺序：脚本首行 shebang 优先，没有 shebang 时按扩展名映射。
/// 映射出来的是解释器**名字**，再交给登录 shell 解析成绝对路径 ——
/// 因为本机 node 走 nvm（`/Users/chen/.nvm/current/bin/node`），写死路径必错。
public struct InterpreterResolver: Sendable {

    public static let extensionMap: [String: String] = [
        "py": "python3",
        "js": "node",
        "sh": "/bin/sh",
    ]

    public enum Failure: Error, Equatable {
        case scriptMissing(path: String)
        case unreadable(path: String)
        case unknownExtension(String)
        case interpreterNotFound(name: String)

        public var message: String {
            switch self {
            case .scriptMissing(let p): return "脚本不存在：\(p)"
            case .unreadable(let p): return "脚本读不出来：\(p)"
            case .unknownExtension(let e): return "不认识的脚本扩展名：.\(e)，且首行没有 shebang"
            case .interpreterNotFound(let n): return "未找到解释器 \(n)"
            }
        }
    }

    private let runner: any CommandRunner
    private let fileSystem: any FileSystem
    private let loginShell: String
    /// 解析结果只缓存在进程生命周期内：nvm 切版本会让上次解析出的路径失效（shape.md 2.3）。
    private let cache: PathCache

    public init(runner: any CommandRunner, fileSystem: any FileSystem, loginShell: String) {
        self.runner = runner
        self.fileSystem = fileSystem
        self.loginShell = loginShell
        self.cache = PathCache()
    }

    public func resolve(scriptPath: String) -> Result<String, Failure> {
        guard fileSystem.fileExists(atPath: scriptPath) else {
            return .failure(.scriptMissing(path: scriptPath))
        }
        guard let data = try? fileSystem.read(atPath: scriptPath) else {
            return .failure(.unreadable(path: scriptPath))
        }

        if let name = Self.shebangInterpreter(inFileStartingWith: data) {
            // shebang 写的通常已经是绝对路径；不是的话照样过一遍解析。
            return resolveName(name)
        }

        let ext = (scriptPath as NSString).pathExtension.lowercased()
        guard let name = Self.extensionMap[ext] else {
            return .failure(.unknownExtension(ext.isEmpty ? "(无扩展名)" : ext))
        }
        return resolveName(name)
    }

    /// 只看文件开头一小段：脚本可能很大，而 shebang 只可能在第一行。
    public static func shebangInterpreter(inFileStartingWith data: Data) -> String? {
        let head = data.prefix(512)
        guard let text = String(data: head, encoding: .utf8) else { return nil }
        guard text.hasPrefix("#!") else { return nil }

        let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let body = firstLine.dropFirst(2).trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }

        let parts = body.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let first = parts.first else { return nil }

        // `#!/usr/bin/env python3` 的真正解释器是 env 后面那个词。
        if (first as NSString).lastPathComponent == "env", parts.count > 1 {
            return parts[1]
        }
        return first
    }

    private func resolveName(_ name: String) -> Result<String, Failure> {
        if name.hasPrefix("/") {
            return fileSystem.isExecutableFile(atPath: name)
                ? .success(name)
                : .failure(.interpreterNotFound(name: name))
        }

        if let cached = cache.value(for: name) {
            return .success(cached)
        }

        guard
            let result = try? runner.run(
                executable: loginShell,
                arguments: ["-ilc", "command -v \(name)"],
                environment: nil,
                timeoutSeconds: 20
            ),
            result.exitCode == 0,
            let path = ExecutablePathFilter.absolutePath(named: name, inShellOutput: result.stdout),
            fileSystem.isExecutableFile(atPath: path)
        else {
            return .failure(.interpreterNotFound(name: name))
        }

        cache.set(path, for: name)
        return .success(path)
    }

    /// 进程内缓存。不落盘，应用重启即失效。
    private final class PathCache: @unchecked Sendable {
        private var storage: [String: String] = [:]
        private let lock = NSLock()

        func value(for name: String) -> String? {
            lock.lock()
            defer { lock.unlock() }
            return storage[name]
        }

        func set(_ path: String, for name: String) {
            lock.lock()
            defer { lock.unlock() }
            storage[name] = path
        }
    }
}
