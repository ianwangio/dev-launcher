import DevLauncherCore
import Foundation

/// 内存文件系统。测试不碰真实磁盘（shape.md 2.6）。
final class FakeFileSystem: FileSystem, @unchecked Sendable {
  private let lock = NSLock()
  private var files: [String: Data] = [:]
  private var executables: Set<String> = []
  private var directories: Set<String> = []
  private(set) var directoriesCreated: [String] = []

  init(files: [String: String] = [:], executables: Set<String> = []) {
    self.files = files.mapValues { Data($0.utf8) }
    self.executables = executables
  }

  func put(_ contents: String, at path: String) {
    lock.lock()
    defer { lock.unlock() }
    files[path] = Data(contents.utf8)
  }

  func putDirectory(at path: String) {
    lock.lock()
    defer { lock.unlock() }
    directories.insert(path)
  }

  func markExecutable(_ path: String) {
    lock.lock()
    defer { lock.unlock() }
    executables.insert(path)
    files[path] = files[path] ?? Data()
  }

  func contents(at path: String) -> String? {
    lock.lock()
    defer { lock.unlock() }
    return files[path].map { String(decoding: $0, as: UTF8.self) }
  }

  func fileExists(atPath path: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return files[path] != nil || executables.contains(path) || directories.contains(path)
  }

  func isDirectory(atPath path: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return directories.contains(path)
  }

  func isExecutableFile(atPath path: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return executables.contains(path)
  }

  func read(atPath path: String) throws -> Data {
    lock.lock()
    defer { lock.unlock() }
    guard let data = files[path] else {
      throw NSError(
        domain: "FakeFileSystem", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "no such file: \(path)"])
    }
    return data
  }

  func write(_ data: Data, toPath path: String) throws {
    lock.lock()
    defer { lock.unlock() }
    files[path] = data
  }

  func createDirectory(atPath path: String) throws {
    lock.lock()
    defer { lock.unlock() }
    directoriesCreated.append(path)
  }
}

/// 按 (可执行文件, 参数) 查表返回固定输出的子进程替身。
final class FakeCommandRunner: CommandRunner, @unchecked Sendable {
  struct Call: Equatable {
    var executable: String
    var arguments: [String]
  }

  private let lock = NSLock()
  private var responses: [String: CommandResult] = [:]
  private var recorded: [Call] = []

  var calls: [Call] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  func stub(executable: String, arguments: [String], result: CommandResult) {
    lock.lock()
    defer { lock.unlock() }
    responses[Self.key(executable, arguments)] = result
  }

  func run(
    executable: String,
    arguments: [String],
    environment: [String: String]?,
    timeoutSeconds: Double
  ) throws -> CommandResult {
    lock.lock()
    recorded.append(Call(executable: executable, arguments: arguments))
    let response = responses[Self.key(executable, arguments)]
    lock.unlock()

    guard let response else {
      return CommandResult(stdout: "", stderr: "no stub", exitCode: 127)
    }
    return response
  }

  private static func key(_ executable: String, _ arguments: [String]) -> String {
    ([executable] + arguments).joined(separator: "\u{1}")
  }
}

/// URL 打开的替身。记录被查过的 scheme 和被打开过的 URL。
final class FakeURLOpener: URLOpener, @unchecked Sendable {
  private let lock = NSLock()
  private var handlers: [String: String]
  private(set) var openedURLs: [String] = []

  init(handlers: [String: String]) {
    self.handlers = handlers
  }

  func handlerName(forScheme scheme: String) -> String? {
    lock.lock()
    defer { lock.unlock() }
    return handlers[scheme]
  }

  func open(_ urlString: String) throws {
    lock.lock()
    defer { lock.unlock() }
    openedURLs.append(urlString)
  }
}

final class FakeApplicationOpener: ApplicationOpener, @unchecked Sendable {
  struct Opened: Equatable {
    var target: String
    var applicationName: String
  }

  private let available: Set<String>
  private(set) var opened: [Opened] = []

  init(available: Set<String>) {
    self.available = available
  }

  func isApplicationAvailable(named name: String) -> Bool {
    available.contains(name)
  }

  func open(target: String, withApplicationNamed name: String) throws {
    opened.append(Opened(target: target, applicationName: name))
  }
}

struct FakeClock: Clock {
  var now: Date
}

/// 内存 Keychain。测试不碰真实 Keychain（shape.md 2.6）。
final class InMemorySecretStore: SecretStore, @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [String: String] = [:]

  func secret(forAccount account: String) throws -> String? {
    lock.lock()
    defer { lock.unlock() }
    return storage[account]
  }

  func setSecret(_ value: String?, forAccount account: String) throws {
    lock.lock()
    defer { lock.unlock() }
    storage[account] = value
  }
}

enum Sample {
  /// 一个解释器齐备的假环境：脚本在、python3/node 解析得到。
  static func environment() -> (FakeFileSystem, FakeCommandRunner) {
    let fs = FakeFileSystem()
    fs.put("#!/usr/bin/env python3\nprint('hi')\n", at: "/tmp/hello.py")
    fs.put("console.log('hi')\n", at: "/tmp/hello.js")
    fs.markExecutable("/usr/bin/python3")
    fs.markExecutable("/Users/test/.nvm/current/bin/node")

    let runner = FakeCommandRunner()
    runner.stub(
      executable: "/bin/zsh",
      arguments: ["-ilc", "command -v python3"],
      result: CommandResult(stdout: "/usr/bin/python3\n", stderr: "", exitCode: 0)
    )
    runner.stub(
      executable: "/bin/zsh",
      arguments: ["-ilc", "command -v node"],
      result: CommandResult(stdout: "/Users/test/.nvm/current/bin/node\n", stderr: "", exitCode: 0)
    )
    return (fs, runner)
  }
}
