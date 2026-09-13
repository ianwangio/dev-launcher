import Foundation

/// 把命中结果变成面板上的候选项：展开模板、查可用性、写清"将要做什么"。
///
/// 这一层**只做存在性查询**（scheme 有没有处理者、解释器在不在、路径存不存在），
/// 不执行、不打开、不写盘。decisions.md Q5 的安全边界在这里和 `Matcher` 一起构成结构保证。
public struct ActionResolver: Sendable {

  private let urlOpener: any URLOpener
  private let fileSystem: any FileSystem
  private let interpreters: InterpreterResolver
  private let applicationOpener: (any ApplicationOpener)?
  private let repositories: [GitHubRepository]
  private let history: [HistoryEntry]

  public init(
    urlOpener: any URLOpener,
    fileSystem: any FileSystem,
    interpreters: InterpreterResolver,
    applicationOpener: (any ApplicationOpener)? = nil,
    repositories: [GitHubRepository] = [],
    history: [HistoryEntry] = []
  ) {
    self.urlOpener = urlOpener
    self.fileSystem = fileSystem
    self.interpreters = interpreters
    self.applicationOpener = applicationOpener
    self.repositories = repositories
    self.history = history
  }

  public func candidates(for matches: [MatchResult]) -> [Candidate] {
    var out: [Candidate] = []
    for match in matches {
      guard passesPathRequirement(match) else { continue }
      for (index, action) in match.rule.actions.enumerated() {
        out.append(contentsOf:
          candidates(
            rule: match.rule,
            captures: match.captures,
            namedValues: match.namedValues,
            index: index,
            action: action
          )
        )
      }
    }
    return out
  }

  /// 文件系统条件在纯匹配阶段不读取磁盘，在这里通过 Port 做最终验证。
  private func passesPathRequirement(_ match: MatchResult) -> Bool {
    guard match.rule.requiresExistingPath || match.rule.requiresExistingDirectory else { return true }
    guard let whole = match.captures.first else { return false }
    let path = NSString(string: whole).expandingTildeInPath
    if match.rule.requiresExistingDirectory {
      return fileSystem.isDirectory(atPath: path)
    }
    return fileSystem.fileExists(atPath: path)
  }

  private func candidates(
    rule: Rule,
    captures: [String],
    namedValues: [String: String],
    index: Int,
    action: Action
  ) -> [Candidate] {
    let id = "\(rule.id)#\(index)"

    switch action {
    case .openURL(let a):
      let url = TemplateExpander.expand(
        a.urlTemplate,
        captures: captures,
        namedValues: namedValues,
        escaping: .percentEncoded
      )
      let availability = urlAvailability(url)
      return [Candidate(
        id: id,
        ruleID: rule.id,
        ruleName: rule.name,
        actionIndex: index,
        title: a.title,
        icon: icon(forURL: url),
        detail: friendlyHint(for: url),
        availability: availability,
        plan: availability.isAvailable ? .open(url: url) : nil
      )]

    case .runScript(let a):
      let scriptPath = NSString(string: a.scriptPath).expandingTildeInPath
      let arguments = a.args.map {
        TemplateExpander.expand(
          $0,
          captures: captures,
          namedValues: namedValues,
          escaping: .raw
        )
      }

      switch interpreters.resolve(scriptPath: scriptPath) {
      case .success(let interpreter):
        let plan = ScriptPlan(
          interpreter: interpreter, scriptPath: scriptPath, arguments: arguments)
        return [Candidate(
          id: id,
          ruleID: rule.id,
          ruleName: rule.name,
          actionIndex: index,
          title: a.title,
          icon: .application(name: "Terminal"),
          detail: "运行脚本 \((scriptPath as NSString).lastPathComponent)",
          availability: .available,
          plan: .script(plan)
        )]
      case .failure(let failure):
        return [Candidate(
          id: id,
          ruleID: rule.id,
          ruleName: rule.name,
          actionIndex: index,
          title: a.title,
          icon: .application(name: "Terminal"),
          detail: "运行脚本 \((scriptPath as NSString).lastPathComponent)",
          availability: .unavailable(reason: failure.message),
          plan: nil
        )]
      }

    case .openPath(let a):
      let rawPath = TemplateExpander.expand(
        a.pathTemplate,
        captures: captures,
        namedValues: namedValues,
        escaping: .raw
      )
      let path = NSString(string: rawPath).expandingTildeInPath
      let availability: Availability =
        fileSystem.fileExists(atPath: path)
        ? .available
        : .unavailable(reason: "文件或文件夹不存在")
      return [Candidate(
        id: id,
        ruleID: rule.id,
        ruleName: rule.name,
        actionIndex: index,
        title: a.title,
        icon: .system(symbolName: "folder"),
        detail: "打开 \((path as NSString).lastPathComponent)",
        availability: availability,
        plan: availability.isAvailable ? .open(url: URL(fileURLWithPath: path).absoluteString) : nil
      )]

    case .openWithApplication(let a):
      let target = TemplateExpander.expand(
        a.targetTemplate,
        captures: captures,
        namedValues: namedValues,
        escaping: .raw
      )
      let isAvailable = applicationOpener?.isApplicationAvailable(named: a.applicationName) == true
      return [Candidate(
        id: id,
        ruleID: rule.id,
        ruleName: rule.name,
        actionIndex: index,
        title: a.title,
        icon: .application(name: a.applicationName),
        detail: "使用 \(a.applicationName) 打开",
        availability: isAvailable
          ? .available
          : .unavailable(reason: "未找到应用 \(a.applicationName)"),
        plan: isAvailable
          ? .openWithApplication(target: target, applicationName: a.applicationName)
          : nil
      )]

    case .copyText(let a):
      let value = TemplateExpander.expand(
        a.textTemplate,
        captures: captures,
        namedValues: namedValues,
        escaping: .raw
      )
      return [Candidate(
        id: id,
        ruleID: rule.id,
        ruleName: rule.name,
        actionIndex: index,
        title: a.title,
        icon: .system(symbolName: "doc.on.doc"),
        detail: "复制处理后的文本",
        availability: .available,
        plan: .copyText(value)
      )]

    case .repoPicker(let a):
      let issueNumber = captures.dropFirst().first.flatMap(Int.init)
      guard !repositories.isEmpty else {
        return [Candidate(
          id: id,
          ruleID: rule.id,
          ruleName: rule.name,
          actionIndex: index,
          issueNumber: issueNumber,
          title: a.title,
          icon: .application(name: "GitHub Desktop"),
          detail: "请先在集成页刷新 GitHub 仓库",
          availability: .unavailable(reason: "尚未读取到 GitHub 仓库"),
          plan: nil
        )]
      }
      return RepoRanker.rank(
        repositories,
        history: history,
        referenceNumber: issueNumber
      ).enumerated().map { rank, repository in
        let url = TemplateExpander.expand(
          a.issueURLTemplate.replacingOccurrences(of: "$repo", with: repository.nameWithOwner),
          captures: captures,
          namedValues: namedValues,
          escaping: .percentEncoded
        )
        return Candidate(
          id: "\(id)#\(repository.nameWithOwner)",
          ruleID: rule.id,
          ruleName: rule.name,
          actionIndex: index,
          repository: repository.nameWithOwner,
          issueNumber: issueNumber,
          title: repository.nameWithOwner,
          icon: .application(name: "GitHub Desktop"),
          detail: repositoryHint(
            repository,
            issueNumber: issueNumber,
            isFirst: rank == 0
          ),
          availability: .available,
          plan: .open(url: url)
        )
      }
    }
  }

  private func repositoryHint(
    _ repository: GitHubRepository,
    issueNumber: Int?,
    isFirst: Bool
  ) -> String {
    let issue = issueNumber.map { "#\($0)" } ?? "对应编号"
    if isFirst, let issueNumber,
      RepoRanker.isRecommended(repository, for: issueNumber)
    {
      return "\(repository.nameWithOwner) · 推荐打开 \(issue)"
    }
    if let latest = repository.latestPullRequestNumber {
      return "\(repository.nameWithOwner) · 最新 PR #\(latest)"
    }
    return "\(repository.nameWithOwner) · 打开 \(issue)"
  }

  private func urlAvailability(_ url: String) -> Availability {
    guard let scheme = Self.scheme(of: url) else {
      return .unavailable(reason: "展开后不是一个合法 URL：\(url)")
    }
    guard urlOpener.handlerName(forScheme: scheme) != nil else {
      return .unavailable(reason: "没有应用注册处理 \(scheme):// ")
    }
    return .available
  }

  private func friendlyHint(for url: String) -> String {
    guard let components = URLComponents(string: url) else { return "打开链接" }
    switch components.scheme {
    case "claude-cli": return "在终端启动 Claude Code"
    case "claude": return "在 Claude Code 中打开此目录"
    case "codex": return "在 Codex 中新建任务"
    case "file": return "使用默认应用打开"
    case "http", "https":
      return components.host.map { "在浏览器打开 \($0)" } ?? "在浏览器打开链接"
    case let scheme?: return "使用 \(scheme) 应用打开"
    case nil: return "打开链接"
    }
  }

  private func icon(forURL url: String) -> CandidateIcon {
    let host = URLComponents(string: url)?.host?.lowercased()
    if host == "linear.app" { return .application(name: "Linear") }
    if host == "github.com" { return .application(name: "GitHub Desktop") }
    return switch Self.scheme(of: url) {
    case "http", "https": .system(symbolName: "safari")
    case "codex": .application(name: "Codex")
    case "claude": .application(name: "Claude")
    case "claude-cli": .application(name: "Terminal")
    case let scheme?: .system(symbolName: scheme == "file" ? "folder" : "arrow.up.forward.app")
    case nil: .system(symbolName: "arrow.up.forward.app")
    }
  }

  static func scheme(of url: String) -> String? {
    guard let colon = url.firstIndex(of: ":"), colon != url.startIndex else { return nil }
    let scheme = String(url[url.startIndex..<colon])
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+-."))
    guard scheme.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
    guard let first = scheme.first, first.isLetter else { return nil }
    return scheme
  }
}
