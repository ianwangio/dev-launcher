import Foundation

/// 面板上的一个候选项。
///
/// `detail` 是 decisions.md Q5 那条安全边界的界面落实：点之前就告诉用户将要做什么。
public struct Candidate: Equatable, Identifiable, Sendable {
  public var id: String
  public var ruleID: String
  public var ruleName: String
  public var actionIndex: Int
  public var repository: String?
  public var issueNumber: Int?
  public var title: String
  public var icon: CandidateIcon
  /// 人类可读的短上下文；完整 URL、命令与参数不进入日常浮层。
  public var detail: String
  public var availability: Availability
  /// 点击后要执行的东西。`availability` 不是 `.available` 时为 nil。
  public var plan: ActionPlan?

  public init(
    id: String,
    ruleID: String,
    ruleName: String,
    actionIndex: Int,
    repository: String? = nil,
    issueNumber: Int? = nil,
    title: String,
    icon: CandidateIcon,
    detail: String,
    availability: Availability,
    plan: ActionPlan?
  ) {
    self.id = id
    self.ruleID = ruleID
    self.ruleName = ruleName
    self.actionIndex = actionIndex
    self.repository = repository
    self.issueNumber = issueNumber
    self.title = title
    self.icon = icon
    self.detail = detail
    self.availability = availability
    self.plan = plan
  }
}

public enum CandidateIcon: Equatable, Sendable {
  case system(symbolName: String)
  case application(name: String)
}

/// 候选项可不可点。不可点时必须带上具体原因 —— shape.md 2.3 / 2.4 要求在渲染时就说清楚，
/// 而不是让用户点了之后静默失败。
public enum Availability: Equatable, Sendable {
  case available
  case unavailable(reason: String)

  public var isAvailable: Bool {
    if case .available = self { return true }
    return false
  }

  public var reason: String? {
    if case .unavailable(let r) = self { return r }
    return nil
  }
}

/// 点击候选项后要执行的具体动作。已经展开完模板，不再含 `$n`。
public enum ActionPlan: Equatable, Sendable {
  case open(url: String)
  case script(ScriptPlan)
  case copyText(String)
  case openWithApplication(target: String, applicationName: String)
}

/// 一次脚本执行的完整参数。解释器已解析成绝对路径。
public struct ScriptPlan: Equatable, Sendable {
  public var interpreter: String
  public var scriptPath: String
  public var arguments: [String]
  public var timeoutSeconds: Double

  public init(
    interpreter: String, scriptPath: String, arguments: [String], timeoutSeconds: Double = 20
  ) {
    self.interpreter = interpreter
    self.scriptPath = scriptPath
    self.arguments = arguments
    self.timeoutSeconds = timeoutSeconds
  }
}
