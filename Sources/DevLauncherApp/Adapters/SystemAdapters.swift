import AppKit
import DevLauncherCore
import Foundation
import UniformTypeIdentifiers

/// 磁盘。Core 里禁止直接碰 `FileManager.default`（B3），都从这里过。
final class DiskFileSystem: FileSystem {
  func fileExists(atPath path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
  }

  func isDirectory(atPath path: String) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  func isExecutableFile(atPath path: String) -> Bool {
    FileManager.default.isExecutableFile(atPath: path)
  }

  func read(atPath path: String) throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: path))
  }

  func write(_ data: Data, toPath path: String) throws {
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
  }

  func createDirectory(atPath path: String) throws {
    try FileManager.default.createDirectory(
      at: URL(fileURLWithPath: path),
      withIntermediateDirectories: true
    )
  }
}

final class SystemClock: Clock {
  var now: Date { Date() }
}

/// 打开 URL，并在打开之前回答"这个 scheme 有没有人处理"。
///
/// 查 handler 是 shape.md 2.4 的要求：`NSWorkspace.open` 对没注册的 scheme 会静默失败
/// 或弹系统错误框，两种都不能接受，所以在面板渲染时就先查一次。
final class WorkspaceURLOpener: URLOpener {
  func handlerName(forScheme scheme: String) -> String? {
    guard let probe = URL(string: "\(scheme)://probe") else { return nil }
    guard let app = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return nil }
    return app.deletingPathExtension().lastPathComponent
  }

  func open(_ urlString: String) throws {
    guard let url = URL(string: urlString) else {
      throw OpenFailure.malformed(urlString)
    }
    guard NSWorkspace.shared.open(url) else {
      throw OpenFailure.refused(urlString)
    }
  }

  enum OpenFailure: Error {
    case malformed(String)
    case refused(String)
  }
}

/// Keychain。Linear API key 只住在这里，不进任何 JSON（decisions.md D11）。
final class KeychainSecretStore: SecretStore {
  private let service = "DevLauncher"

  func secret(forAccount account: String) throws -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data else {
      throw KeychainFailure.osStatus(status)
    }
    return String(data: data, encoding: .utf8)
  }

  func setSecret(_ value: String?, forAccount account: String) throws {
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(base as CFDictionary)

    guard let value, let data = value.data(using: .utf8) else { return }
    var insert = base
    insert[kSecValueData as String] = data
    let status = SecItemAdd(insert as CFDictionary, nil)
    guard status == errSecSuccess else { throw KeychainFailure.osStatus(status) }
  }

  enum KeychainFailure: Error {
    case osStatus(OSStatus)
  }
}

/// 剪贴板。只暴露 `changeCount` 和取字符串两件事 —— 轮询策略在 Core 的 `ClipboardGate`。
final class SystemPasteboard: PasteboardSource {
  var changeCount: Int { NSPasteboard.general.changeCount }

  func snapshot() -> PasteboardSnapshot {
    let board = NSPasteboard.general
    let filePaths =
      (board.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]
      ) as? [URL] ?? []).map(\.path)
    let richText = board.data(forType: .rtf).flatMap {
      NSAttributedString(rtf: $0, documentAttributes: nil)?.string
    }
    return PasteboardSnapshot(
      plainText: board.string(forType: .string),
      urlString: board.string(forType: .URL),
      filePaths: filePaths,
      richText: richText
    )
  }

  func currentString() -> String? {
    NSPasteboard.general.string(forType: .string)
  }

  func writeString(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
  }
}

final class WorkspaceApplicationContext: ApplicationContextSource {
  var frontmostBundleIdentifier: String? {
    NSWorkspace.shared.frontmostApplication?.bundleIdentifier
  }
}

struct InstalledApplicationDescriptor: Identifiable, Equatable {
  let name: String
  let bundleIdentifier: String

  var id: String { bundleIdentifier }
}

@MainActor
final class ApplicationSelectionAdapter {
  func selectApplications() -> [InstalledApplicationDescriptor] {
    let panel = NSOpenPanel()
    panel.title = "选择要忽略的应用"
    panel.message = "可以一次选择多个应用。"
    panel.prompt = "加入列表"
    panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    panel.allowedContentTypes = [.applicationBundle]
    panel.allowsMultipleSelection = true
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.resolvesAliases = true
    guard panel.runModal() == .OK else { return [] }

    var identifiers = Set<String>()
    return panel.urls.compactMap(ApplicationIconProvider.descriptor(applicationURL:)).filter {
      identifiers.insert($0.bundleIdentifier).inserted
    }
  }
}

enum ApplicationIconProvider {
  static func icon(named applicationName: String) -> NSImage? {
    if let running = NSWorkspace.shared.runningApplications.first(where: {
      $0.localizedName?.localizedCaseInsensitiveCompare(applicationName) == .orderedSame
    }), let icon = running.icon {
      return icon
    }
    guard let url = applicationURL(named: applicationName)
    else { return nil }
    return NSWorkspace.shared.icon(forFile: url.path)
  }

  static func applicationURL(named applicationName: String) -> URL? {
    if let running = NSWorkspace.shared.runningApplications.first(where: {
      $0.localizedName?.localizedCaseInsensitiveCompare(applicationName) == .orderedSame
    }), let url = running.bundleURL {
      return url
    }
    guard let bundleIdentifier = knownBundleIdentifiers[applicationName] else { return nil }
    return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
  }

  static func descriptor(bundleIdentifier: String) -> InstalledApplicationDescriptor {
    if let applicationURL = NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: bundleIdentifier),
      let descriptor = descriptor(applicationURL: applicationURL)
    {
      return descriptor
    }
    return InstalledApplicationDescriptor(name: bundleIdentifier, bundleIdentifier: bundleIdentifier)
  }

  static func descriptor(applicationURL: URL) -> InstalledApplicationDescriptor? {
    guard let bundle = Bundle(url: applicationURL),
      let bundleIdentifier = bundle.bundleIdentifier
    else { return nil }
    let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
    let bundleName = bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
    let name = displayName ?? bundleName ?? applicationURL.deletingPathExtension().lastPathComponent
    return InstalledApplicationDescriptor(name: name, bundleIdentifier: bundleIdentifier)
  }

  static func icon(bundleIdentifier: String) -> NSImage? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    else { return nil }
    return NSWorkspace.shared.icon(forFile: url.path)
  }

  private static let knownBundleIdentifiers = [
    "Codex": "com.openai.codex",
    "Claude": "com.anthropic.claudefordesktop",
    "Finder": "com.apple.finder",
    "Terminal": "com.apple.Terminal",
    "iTerm2": "com.googlecode.iterm2",
    "iTerm": "com.googlecode.iterm2",
    "Zed": "dev.zed.Zed",
    "Google Chrome": "com.google.Chrome",
    "GitHub Desktop": "com.github.GitHubClient",
    "Linear": "com.linear",
    "Safari": "com.apple.Safari",
  ]
}

final class WorkspaceApplicationOpener: ApplicationOpener {
  func isApplicationAvailable(named name: String) -> Bool {
    ApplicationIconProvider.applicationURL(named: name) != nil
  }

  func open(target: String, withApplicationNamed name: String) throws {
    guard let applicationURL = ApplicationIconProvider.applicationURL(named: name) else {
      throw Failure.applicationMissing(name)
    }
    let targetURL: URL
    if let parsed = URL(string: target), parsed.scheme != nil {
      targetURL = parsed
    } else {
      targetURL = URL(fileURLWithPath: NSString(string: target).expandingTildeInPath)
    }
    if name == "Finder" {
      NSWorkspace.shared.activateFileViewerSelecting([targetURL])
      return
    }
    NSWorkspace.shared.open(
      [targetURL],
      withApplicationAt: applicationURL,
      configuration: NSWorkspace.OpenConfiguration()
    )
  }

  enum Failure: Error {
    case applicationMissing(String)
  }
}

/// 本期没有任何功能走网络（shape.md 2.2：Linear 主路径不调 API），
/// 但 Port 要有实现才能构造 Core 的对象。真正接 Linear API 时替换这里。
final class URLSessionHTTPClient: HTTPClient {
  func post(url: String, headers: [String: String], body: Data, timeoutSeconds: Double) throws
    -> HTTPResponse
  {
    guard let target = URL(string: url) else {
      throw Failure.malformedURL(url)
    }
    var request = URLRequest(url: target, timeoutInterval: timeoutSeconds)
    request.httpMethod = "POST"
    request.httpBody = body
    headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

    let semaphore = DispatchSemaphore(value: 0)
    let box = ResponseBox()
    URLSession.shared.dataTask(with: request) { data, response, error in
      box.fill(data: data, response: response as? HTTPURLResponse, error: error)
      semaphore.signal()
    }.resume()

    guard semaphore.wait(timeout: .now() + timeoutSeconds) == .success else {
      throw Failure.timedOut(timeoutSeconds)
    }
    return try box.result()
  }

  enum Failure: Error {
    case malformedURL(String)
    case timedOut(Double)
    case transport(String)
  }

  private final class ResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var response: HTTPURLResponse?
    private var error: (any Error)?

    func fill(data: Data?, response: HTTPURLResponse?, error: (any Error)?) {
      lock.lock()
      defer { lock.unlock() }
      self.data = data
      self.response = response
      self.error = error
    }

    func result() throws -> HTTPResponse {
      lock.lock()
      defer { lock.unlock() }
      if let error { throw Failure.transport(String(describing: error)) }
      return HTTPResponse(body: data ?? Data(), statusCode: response?.statusCode ?? 0)
    }
  }
}

/// 应用数据目录与「在 Finder 中显示」。
///
/// 单独放在 Adapters 是因为 B3 把 `FileManager.default` / `NSWorkspace` 这些符号
/// 限死在这个目录里：界面层想要一个路径，就从这里要，不自己去问系统。
enum SystemPaths {
  static func applicationSupportDirectory(named name: String) -> String {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first
    let root = base ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
    return root.appendingPathComponent(name).path
  }
}

final class FinderRevealer: Sendable {
  func reveal(path: String, inDirectory directory: String) {
    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: directory)
  }
}
