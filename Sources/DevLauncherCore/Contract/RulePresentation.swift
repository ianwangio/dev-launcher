import Foundation

public enum RuleOrigin: Equatable, Sendable {
  case builtin
  case custom
}

public struct RuleCapabilities: Equatable, Sendable {
  public var canEdit: Bool
  public var canDelete: Bool
  public var canReorder: Bool
  public var canDuplicate: Bool

  public static let builtin = RuleCapabilities(
    canEdit: false,
    canDelete: false,
    canReorder: false,
    canDuplicate: true
  )

  public static let custom = RuleCapabilities(
    canEdit: true,
    canDelete: true,
    canReorder: true,
    canDuplicate: true
  )
}

public enum RuleIconKind: Equatable, Sendable {
  case localPath
  case linear
  case github
  case web
  case script
  case copy
  case application(name: String)
  case custom
}

public struct RulePresentation: Identifiable, Equatable, Sendable {
  public var id: String
  public var name: String
  public var isEnabled: Bool
  public var origin: RuleOrigin
  public var capabilities: RuleCapabilities
  public var icon: RuleIconKind
  public var subtitle: String
  public var matchSummary: String
  public var actionTitles: [String]
  public var actionIcons: [CandidateIcon]
  public var shortContext: String

  public static func project(_ rule: Rule) -> RulePresentation {
    let builtin = BuiltinIdentity(rawValue: rule.id)
    let origin: RuleOrigin = builtin == nil ? .custom : .builtin

    return RulePresentation(
      id: rule.id,
      name: rule.name,
      isEnabled: rule.enabled,
      origin: origin,
      capabilities: origin == .builtin ? .builtin : .custom,
      icon: builtin?.icon ?? inferredIcon(for: rule),
      subtitle: subtitle(for: rule, builtin: builtin),
      matchSummary: rule.condition.displaySummary,
      actionTitles: rule.actions.map(\.title),
      actionIcons: rule.actions.map(ActionCatalog.icon),
      shortContext: shortContext(for: builtin)
    )
  }

  private static func subtitle(for rule: Rule, builtin: BuiltinIdentity?) -> String {
    switch builtin {
    case .localPath: "匹配本地文件夹，提供快捷操作"
    case .linear: "匹配 Linear issue 链接"
    case .github: "匹配 GitHub issue 编号"
    case nil: "\(rule.actions.count) 个动作"
    }
  }

  private static func shortContext(for builtin: BuiltinIdentity?) -> String {
    switch builtin {
    case .localPath: "本地文件夹"
    case .linear: "Linear"
    case .github: "GitHub"
    case nil: "自定义规则"
    }
  }

  private static func inferredIcon(for rule: Rule) -> RuleIconKind {
    if condition(
      rule.condition,
      contains: { predicate in
        predicate.field == .urlHost && predicate.value.localizedCaseInsensitiveContains("github")
      }) || rule.actions.contains(where: { if case .repoPicker = $0 { true } else { false } })
    {
      return .github
    }
    if condition(
      rule.condition,
      contains: { predicate in
        predicate.field == .urlHost && predicate.value.localizedCaseInsensitiveContains("linear")
      })
    {
      return .linear
    }
    if condition(
      rule.condition,
      contains: { predicate in
        [.urlScheme, .urlHost, .urlPath, .urlQuery].contains(predicate.field)
      })
    {
      return .web
    }
    for action in rule.actions {
      switch action {
      case .openWithApplication(let value): return .application(name: value.applicationName)
      case .runScript: return .script
      case .copyText: return .copy
      case .openPath: return .localPath
      case .openURL(let value):
        guard let scheme = URLComponents(string: value.urlTemplate)?.scheme else { return .web }
        if scheme == "http" || scheme == "https" { return .web }
        if scheme.hasPrefix("codex") { return .application(name: "Codex") }
        if scheme.hasPrefix("claude") { return .application(name: "Claude") }
      case .repoPicker: return .github
      }
    }
    if condition(
      rule.condition,
      contains: { predicate in
        [.fileExists, .fileKind, .fileExtension].contains(predicate.field)
      })
    {
      return .localPath
    }
    return .custom
  }

  private static func condition(
    _ expression: ConditionExpression,
    contains predicate: (ConditionPredicate) -> Bool
  ) -> Bool {
    switch expression {
    case .predicate(let value): return predicate(value)
    case .group(let group): return group.children.contains { condition($0, contains: predicate) }
    }
  }
}

public struct RuleLibraryPresentation: Equatable, Sendable {
  public var builtin: [RulePresentation]
  public var custom: [RulePresentation]

  public init(ruleSet: RuleSet, searchText: String = "") {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let items = ruleSet.rules
      .map(RulePresentation.project)
      .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }

    self.builtin = items.filter { $0.origin == .builtin }
    self.custom = items.filter { $0.origin == .custom }
  }
}

private enum BuiltinIdentity: String {
  case localPath = "builtin.local-path"
  case linear = "builtin.linear-issue"
  case github = "builtin.github-issue-number"

  var icon: RuleIconKind {
    switch self {
    case .localPath: .localPath
    case .linear: .linear
    case .github: .github
    }
  }
}
