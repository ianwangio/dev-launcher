import Foundation

/// 一条规则命中后可以执行的动作。
///
/// 这个枚举连同 `Rule` 是规则 schema 的**唯一真相**（shape.md 第 0 节）：
/// `rules.json` 是它的序列化结果，界面表单是它的投影，内置预设是它的实例。
/// 界面层不得另外声明一份"稍微不一样的"版本 —— 由 B4 守。
public enum Action: Codable, Equatable, Sendable {
  /// 展开 URL 模板并交给系统默认应用打开。
  case openURL(OpenURLAction)
  /// 用系统默认处理者打开文件或文件夹。
  case openPath(OpenPathAction)
  /// 用用户选择的应用打开目标。
  case openWithApplication(OpenWithApplicationAction)
  /// 用解释器执行一个本地脚本。
  case runScript(RunScriptAction)
  /// 把展开后的文本写回剪贴板。
  case copyText(CopyTextAction)
  /// 内置动作：列出 GitHub repo 供选择，再打开对应 issue。
  case repoPicker(RepoPickerAction)

  public var title: String {
    switch self {
    case .openURL(let a): return a.title
    case .openPath(let a): return a.title
    case .openWithApplication(let a): return a.title
    case .runScript(let a): return a.title
    case .copyText(let a): return a.title
    case .repoPicker(let a): return a.title
    }
  }

  // MARK: Codable

  /// JSON 里的类型判别字段，形状见 decisions.md D5。
  private enum Discriminator: String, CodingKey {
    case type
  }

  private enum Kind: String, Codable {
    case openURL
    case openPath
    case openWithApplication
    case runScript
    case copyText
    case repoPicker
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: Discriminator.self)
    switch try container.decode(Kind.self, forKey: .type) {
    case .openURL: self = .openURL(try OpenURLAction(from: decoder))
    case .openPath: self = .openPath(try OpenPathAction(from: decoder))
    case .openWithApplication:
      self = .openWithApplication(try OpenWithApplicationAction(from: decoder))
    case .runScript: self = .runScript(try RunScriptAction(from: decoder))
    case .copyText: self = .copyText(try CopyTextAction(from: decoder))
    case .repoPicker: self = .repoPicker(try RepoPickerAction(from: decoder))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Discriminator.self)
    switch self {
    case .openURL(let a):
      try container.encode(Kind.openURL, forKey: .type)
      try a.encode(to: encoder)
    case .openPath(let a):
      try container.encode(Kind.openPath, forKey: .type)
      try a.encode(to: encoder)
    case .openWithApplication(let a):
      try container.encode(Kind.openWithApplication, forKey: .type)
      try a.encode(to: encoder)
    case .runScript(let a):
      try container.encode(Kind.runScript, forKey: .type)
      try a.encode(to: encoder)
    case .copyText(let a):
      try container.encode(Kind.copyText, forKey: .type)
      try a.encode(to: encoder)
    case .repoPicker(let a):
      try container.encode(Kind.repoPicker, forKey: .type)
      try a.encode(to: encoder)
    }
  }
}

public struct OpenPathAction: Codable, Equatable, Sendable {
  public var title: String
  public var pathTemplate: String

  public init(title: String, pathTemplate: String) {
    self.title = title
    self.pathTemplate = pathTemplate
  }
}

public struct OpenWithApplicationAction: Codable, Equatable, Sendable {
  public var title: String
  public var applicationName: String
  public var targetTemplate: String

  public init(title: String, applicationName: String, targetTemplate: String) {
    self.title = title
    self.applicationName = applicationName
    self.targetTemplate = targetTemplate
  }
}

/// 打开 URL。`urlTemplate` 里 `$0` 是整段匹配，`$1`..`$9` 是捕获组。
public struct OpenURLAction: Codable, Equatable, Sendable {
  public var title: String
  public var urlTemplate: String

  public init(title: String, urlTemplate: String) {
    self.title = title
    self.urlTemplate = urlTemplate
  }
}

/// 执行本地脚本。`args` 的每一项同样支持 `$0`..`$9`，但不做 URL 编码。
public struct RunScriptAction: Codable, Equatable, Sendable {
  public var title: String
  public var scriptPath: String
  public var args: [String]

  public init(title: String, scriptPath: String, args: [String]) {
    self.title = title
    self.scriptPath = scriptPath
    self.args = args
  }
}

public struct CopyTextAction: Codable, Equatable, Sendable {
  public var title: String
  public var textTemplate: String

  public init(title: String, textTemplate: String) {
    self.title = title
    self.textTemplate = textTemplate
  }
}

/// 列出 GitHub repo 供选择。`issueURLTemplate` 里 `$repo` 由用户选中的 repo 填入。
public struct RepoPickerAction: Codable, Equatable, Sendable {
  public var title: String
  public var issueURLTemplate: String

  public init(title: String, issueURLTemplate: String) {
    self.title = title
    self.issueURLTemplate = issueURLTemplate
  }
}
