import Foundation

// 七个 Port。全部 Sendable：启动时要在后台预热解释器路径缓存，adapter 得能跨线程传。
// Core 的一切副作用都从这里出去，真实实现全在 DevLauncherApp/Adapters/。
// 这是 decisions.md D3 的硬约束，也是没有图形界面时还能跑测试的唯一划法。

// MARK: - 子进程

public struct CommandResult: Equatable, Sendable {
  public var stdout: String
  public var stderr: String
  public var exitCode: Int32

  public init(stdout: String, stderr: String, exitCode: Int32) {
    self.stdout = stdout
    self.stderr = stderr
    self.exitCode = exitCode
  }
}

public enum CommandError: Error, Equatable {
  case notExecutable(String)
  case timedOut(after: Double)
  case launchFailed(String)
}

/// 执行一个子进程。实现必须直接 exec 可执行文件，不得把参数拼进 shell 字符串
/// （decisions.md D6 / D9：剪贴板内容会流进这里）。
public protocol CommandRunner: Sendable {
  func run(
    executable: String,
    arguments: [String],
    environment: [String: String]?,
    timeoutSeconds: Double
  ) throws -> CommandResult
}

// MARK: - 网络

public struct HTTPResponse: Equatable, Sendable {
  public var body: Data
  public var statusCode: Int

  public init(body: Data, statusCode: Int) {
    self.body = body
    self.statusCode = statusCode
  }
}

public protocol HTTPClient: Sendable {
  func post(url: String, headers: [String: String], body: Data, timeoutSeconds: Double) throws
    -> HTTPResponse
}

// MARK: - 文件系统

public protocol FileSystem: Sendable {
  func fileExists(atPath path: String) -> Bool
  func isDirectory(atPath path: String) -> Bool
  func isExecutableFile(atPath path: String) -> Bool
  func read(atPath path: String) throws -> Data
  func write(_ data: Data, toPath path: String) throws
  func createDirectory(atPath path: String) throws
}

// MARK: - 时钟

/// Core 不许调 `Date()`（由 B3 守），需要当前时间就从这里拿。
public protocol Clock: Sendable {
  var now: Date { get }
}

// MARK: - 机密

/// Keychain 的抽象。测试用内存实现，不碰真实 Keychain（shape.md 2.6）。
public protocol SecretStore: Sendable {
  func secret(forAccount account: String) throws -> String?
  func setSecret(_ value: String?, forAccount account: String) throws
}

// MARK: - 打开 URL

public protocol URLOpener: Sendable {
  /// 该 scheme 有没有注册的处理者。查不到就把候选项置灰（shape.md 2.4）。
  func handlerName(forScheme scheme: String) -> String?
  func open(_ urlString: String) throws
}

public protocol ApplicationOpener: Sendable {
  func isApplicationAvailable(named name: String) -> Bool
  func open(target: String, withApplicationNamed name: String) throws
}

// MARK: - 剪贴板

public protocol PasteboardSource: Sendable {
  /// 只有它变了才去取内容。一次整数比较，这是"轻量"的全部含义（decisions.md D4）。
  var changeCount: Int { get }
  func snapshot() -> PasteboardSnapshot
  func currentString() -> String?
  func writeString(_ value: String)
}

public protocol ApplicationContextSource: Sendable {
  var frontmostBundleIdentifier: String? { get }
}
