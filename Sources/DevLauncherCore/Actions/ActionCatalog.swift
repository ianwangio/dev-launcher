import Foundation

public enum ActionKind: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
  case openURL
  case openPath
  case openWithApplication
  case runScript
  case copyText
  case repoPicker

  public var id: String { rawValue }
}

public enum ActionCategory: String, CaseIterable, Equatable, Sendable, Identifiable {
  case path
  case url
  case automation

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .path: "路径与文件"
    case .url: "URL 与网页"
    case .automation: "自动化"
    }
  }
}

public struct ActionDescriptor: Equatable, Sendable, Identifiable {
  public var kind: ActionKind
  public var title: String
  public var summary: String
  public var symbolName: String
  public var category: ActionCategory

  public var id: ActionKind { kind }
}

public struct ActionTemplate: Equatable, Sendable, Identifiable {
  public var id: String
  public var title: String
  public var summary: String
  public var symbolName: String
  public var category: ActionCategory
  public var action: Action
}

public struct ActionValidation: Equatable, Sendable {
  public var isValid: Bool
  public var message: String?

  public static let valid = ActionValidation(isValid: true, message: nil)
}

public struct CandidatePresentation: Equatable, Sendable {
  public var title: String
  public var context: String
  public var symbolName: String
}

public enum ActionCatalog {
  public static let descriptors: [ActionDescriptor] = [
    ActionDescriptor(
      kind: .openURL, title: "打开链接", summary: "在默认浏览器中打开链接", symbolName: "safari",
      category: .url),
    ActionDescriptor(
      kind: .openPath, title: "打开文件或文件夹", summary: "使用系统默认应用打开目标", symbolName: "folder",
      category: .path),
    ActionDescriptor(
      kind: .openWithApplication, title: "用指定应用打开", summary: "选择应用打开链接或文件", symbolName: "app",
      category: .path),
    ActionDescriptor(
      kind: .runScript, title: "运行脚本", summary: "运行本地脚本或自动化任务", symbolName: "terminal",
      category: .automation),
    ActionDescriptor(
      kind: .copyText, title: "复制文本", summary: "把生成的文本复制到剪贴板", symbolName: "doc.on.doc",
      category: .automation),
    ActionDescriptor(
      kind: .repoPicker, title: "GitHub 仓库选择", summary: "选择仓库并打开对应编号",
      symbolName: "chevron.left.forwardslash.chevron.right", category: .automation),
  ]

  public static let templates: [ActionTemplate] = [
    ActionTemplate(
      id: "finder",
      title: "Finder",
      summary: "在 Finder 中显示",
      symbolName: "face.smiling",
      category: .path,
      action: .openWithApplication(
        OpenWithApplicationAction(
          title: "在 Finder 中显示", applicationName: "Finder", targetTemplate: "{{匹配内容}}")
      )
    ),
    ActionTemplate(
      id: "terminal",
      title: "终端",
      summary: "在终端中打开",
      symbolName: "terminal",
      category: .path,
      action: .openWithApplication(
        OpenWithApplicationAction(
          title: "在终端中打开", applicationName: "Terminal", targetTemplate: "{{匹配内容}}")
      )
    ),
    ActionTemplate(
      id: "iterm2",
      title: "iTerm2",
      summary: "在 iTerm2 中打开路径",
      symbolName: "terminal",
      category: .path,
      action: .openWithApplication(
        OpenWithApplicationAction(
          title: "在 iTerm2 中打开", applicationName: "iTerm2", targetTemplate: "{{匹配内容}}")
      )
    ),
    ActionTemplate(
      id: "claude-code",
      title: "Claude Code",
      summary: "在 Claude Code 中打开",
      symbolName: "sparkles",
      category: .path,
      action: .openURL(
        OpenURLAction(title: "在 Claude Code 中打开", urlTemplate: "claude://code/new?folder=$0"))
    ),
    ActionTemplate(
      id: "codex",
      title: "Codex",
      summary: "在 Codex 中打开",
      symbolName: "chevron.left.forwardslash.chevron.right",
      category: .path,
      action: .openURL(
        OpenURLAction(title: "在 Codex 中打开", urlTemplate: "codex://threads/new?path=$0"))
    ),
    ActionTemplate(
      id: "zed",
      title: "Zed",
      summary: "在 Zed 中打开路径",
      symbolName: "app",
      category: .path,
      action: .openWithApplication(
        OpenWithApplicationAction(
          title: "在 Zed 中打开", applicationName: "Zed", targetTemplate: "{{匹配内容}}")
      )
    ),
    ActionTemplate(
      id: "browser",
      title: "默认浏览器",
      summary: "在默认浏览器中打开",
      symbolName: "safari",
      category: .url,
      action: .openURL(OpenURLAction(title: "在浏览器中打开", urlTemplate: "$0"))
    ),
    ActionTemplate(
      id: "chrome",
      title: "Google Chrome",
      summary: "在 Chrome 中打开 URL",
      symbolName: "globe",
      category: .url,
      action: .openWithApplication(
        OpenWithApplicationAction(
          title: "在 Chrome 中打开", applicationName: "Google Chrome", targetTemplate: "{{匹配内容}}")
      )
    ),
    ActionTemplate(
      id: "linear",
      title: "Linear",
      summary: "在 Linear 中打开",
      symbolName: "line.3.horizontal.decrease.circle",
      category: .url,
      action: .openURL(
        OpenURLAction(title: "在 Linear 中打开", urlTemplate: "https://linear.app/issue/$0"))
    ),
    ActionTemplate(
      id: "github",
      title: "GitHub",
      summary: "选择仓库并打开 issue",
      symbolName: "chevron.left.forwardslash.chevron.right",
      category: .automation,
      action: .repoPicker(
        RepoPickerAction(title: "选择仓库并打开", issueURLTemplate: "https://github.com/$repo/issues/$1")
      )
    ),
  ]

  public static func descriptors(in category: ActionCategory) -> [ActionDescriptor] {
    descriptors.filter { $0.category == category }
  }

  public static func templates(in category: ActionCategory) -> [ActionTemplate] {
    templates.filter { $0.category == category }
  }

  public static func icon(for action: Action) -> CandidateIcon {
    switch action {
    case .openURL(let value):
      let host = URLComponents(string: value.urlTemplate)?.host?.lowercased()
      if host == "linear.app" { return .application(name: "Linear") }
      if host == "github.com" { return .application(name: "GitHub Desktop") }
      switch URLComponents(string: value.urlTemplate)?.scheme {
      case "codex": return .application(name: "Codex")
      case "claude": return .application(name: "Claude")
      case "claude-cli": return .application(name: "Terminal")
      default: return .system(symbolName: "safari")
      }
    case .openPath: return .system(symbolName: "folder")
    case .openWithApplication(let value): return .application(name: value.applicationName)
    case .runScript: return .application(name: "Terminal")
    case .copyText: return .system(symbolName: "doc.on.doc")
    case .repoPicker: return .application(name: "GitHub Desktop")
    }
  }

  public static func defaultAction(for kind: ActionKind) -> Action {
    switch kind {
    case .openURL: .openURL(OpenURLAction(title: "在浏览器中打开", urlTemplate: "$0"))
    case .openPath: .openPath(OpenPathAction(title: "打开文件或文件夹", pathTemplate: "{{匹配内容}}"))
    case .openWithApplication:
      .openWithApplication(
        OpenWithApplicationAction(
          title: "用指定应用打开", applicationName: "Finder", targetTemplate: "{{匹配内容}}")
      )
    case .runScript:
      .runScript(RunScriptAction(title: "运行脚本", scriptPath: "~/script.py", args: ["{{匹配内容}}"]))
    case .copyText: .copyText(CopyTextAction(title: "复制文本", textTemplate: "{{匹配内容}}"))
    case .repoPicker:
      .repoPicker(
        RepoPickerAction(
          title: "选择 GitHub 仓库", issueURLTemplate: "https://github.com/$repo/issues/$1")
      )
    }
  }

  public static func validate(_ action: Action) -> ActionValidation {
    switch action {
    case .openURL(let value):
      return required(value.urlTemplate, message: "请输入链接模板")
    case .openPath(let value):
      return required(value.pathTemplate, message: "请输入路径模板")
    case .openWithApplication(let value):
      if value.applicationName.isEmpty {
        return ActionValidation(isValid: false, message: "请选择应用")
      }
      return required(value.targetTemplate, message: "请输入打开目标")
    case .runScript(let value):
      return required(value.scriptPath, message: "请选择脚本")
    case .copyText(let value):
      return required(value.textTemplate, message: "请输入文本模板")
    case .repoPicker(let value):
      return required(value.issueURLTemplate, message: "请输入 GitHub 链接模板")
    }
  }

  public static func preview(_ action: Action, values: [String: String] = [:])
    -> CandidatePresentation
  {
    let context = values["匹配内容"] ?? "匹配内容"
    switch action {
    case .openURL(let value):
      return CandidatePresentation(
        title: value.title, context: shortHost(value.urlTemplate) ?? context, symbolName: "safari")
    case .openPath(let value):
      return CandidatePresentation(
        title: value.title, context: (context as NSString).lastPathComponent, symbolName: "folder")
    case .openWithApplication(let value):
      return CandidatePresentation(
        title: value.title, context: value.applicationName, symbolName: "app")
    case .runScript(let value):
      return CandidatePresentation(
        title: value.title, context: (value.scriptPath as NSString).lastPathComponent,
        symbolName: "terminal")
    case .copyText(let value):
      return CandidatePresentation(title: value.title, context: context, symbolName: "doc.on.doc")
    case .repoPicker(let value):
      return CandidatePresentation(
        title: value.title, context: "GitHub", symbolName: "chevron.left.forwardslash.chevron.right"
      )
    }
  }

  private static func required(_ value: String, message: String) -> ActionValidation {
    value.isEmpty ? ActionValidation(isValid: false, message: message) : .valid
  }

  private static func shortHost(_ value: String) -> String? {
    URLComponents(string: value)?.host
  }
}
