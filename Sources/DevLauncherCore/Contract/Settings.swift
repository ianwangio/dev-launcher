import Foundation

public struct Settings: Codable, Equatable, Sendable {
  public static let currentVersion = 7

  public var version: Int
  public var listening: ListeningSettings
  public var panel: PanelSettings
  public var linearWorkspace: String
  public var linearTeamKeys: [String]
  public var activityRetentionLimit: Int
  /// nil 表示尚未初始化；首次获取仓库后选择最后更新的 10 个。空数组表示明确全部取消。
  public var githubSelectedRepositories: [String]?

  public static let `default` = Settings(
    version: currentVersion,
    listening: .default,
    panel: .default,
    linearWorkspace: "",
    linearTeamKeys: [],
    activityRetentionLimit: ActivityLedger.defaultRetentionLimit,
    githubSelectedRepositories: nil
  )

  public init(
    version: Int = Settings.currentVersion,
    listening: ListeningSettings,
    panel: PanelSettings,
    linearWorkspace: String,
    linearTeamKeys: [String],
    activityRetentionLimit: Int = ActivityLedger.defaultRetentionLimit,
    githubSelectedRepositories: [String]? = nil
  ) {
    self.version = version
    self.listening = listening
    self.panel = panel
    self.linearWorkspace = linearWorkspace
    self.linearTeamKeys = linearTeamKeys
    self.activityRetentionLimit = activityRetentionLimit
    self.githubSelectedRepositories = githubSelectedRepositories
  }

  /// v1 construction surface retained for existing callers and migration tests.
  public init(
    pollIntervalMilliseconds: Int,
    maxClipboardLength: Int,
    panelAutoDismissSeconds: Double,
    linearWorkspace: String,
    linearTeamKeys: [String]
  ) {
    var listening = ListeningSettings.default
    listening.pollIntervalMilliseconds = pollIntervalMilliseconds
    listening.maximumContentLength = maxClipboardLength
    var panel = PanelSettings.default
    panel.autoDismissSeconds = panelAutoDismissSeconds
    self.init(
      listening: listening,
      panel: panel,
      linearWorkspace: linearWorkspace,
      linearTeamKeys: linearTeamKeys
    )
  }

  public var pollIntervalMilliseconds: Int {
    get { listening.pollIntervalMilliseconds }
    set { listening.pollIntervalMilliseconds = newValue }
  }

  public var maxClipboardLength: Int {
    get { listening.maximumContentLength }
    set { listening.maximumContentLength = newValue }
  }

  public var panelAutoDismissSeconds: Double {
    get { panel.autoDismissSeconds }
    set { panel.autoDismissSeconds = newValue }
  }

  private enum CodingKeys: String, CodingKey {
    case version
    case listening
    case panel
    case linearWorkspace
    case linearTeamKeys
    case activityRetentionLimit
    case githubSelectedRepositories
    case pollIntervalMilliseconds
    case maxClipboardLength
    case panelAutoDismissSeconds
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    linearWorkspace = try container.decodeIfPresent(String.self, forKey: .linearWorkspace) ?? ""
    linearTeamKeys = try container.decodeIfPresent([String].self, forKey: .linearTeamKeys) ?? []
    let decodedRetentionLimit =
      try container.decodeIfPresent(Int.self, forKey: .activityRetentionLimit)
      ?? ActivityLedger.defaultRetentionLimit
    activityRetentionLimit = ActivityLedger.supportedRetentionLimits.contains(decodedRetentionLimit)
      ? decodedRetentionLimit : ActivityLedger.defaultRetentionLimit
    githubSelectedRepositories = try container.decodeIfPresent(
      [String].self, forKey: .githubSelectedRepositories)

    if let listening = try container.decodeIfPresent(ListeningSettings.self, forKey: .listening),
      let panel = try container.decodeIfPresent(PanelSettings.self, forKey: .panel)
    {
      self.listening = listening
      self.panel = panel
    } else {
      var listening = ListeningSettings.default
      listening.pollIntervalMilliseconds =
        try container.decodeIfPresent(Int.self, forKey: .pollIntervalMilliseconds) ?? 500
      listening.maximumContentLength =
        try container.decodeIfPresent(Int.self, forKey: .maxClipboardLength) ?? 4096
      var panel = PanelSettings.default
      panel.autoDismissSeconds =
        try container.decodeIfPresent(Double.self, forKey: .panelAutoDismissSeconds) ?? 5
      self.listening = listening
      self.panel = panel
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(version, forKey: .version)
    try container.encode(listening, forKey: .listening)
    try container.encode(panel, forKey: .panel)
    try container.encode(linearWorkspace, forKey: .linearWorkspace)
    try container.encode(linearTeamKeys, forKey: .linearTeamKeys)
    try container.encode(activityRetentionLimit, forKey: .activityRetentionLimit)
    try container.encodeIfPresent(githubSelectedRepositories, forKey: .githubSelectedRepositories)
  }
}
