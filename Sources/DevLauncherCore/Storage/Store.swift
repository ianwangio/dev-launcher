import Foundation

/// `rules.json` / `settings.json` 的读写。
///
/// 编码器固定 `.sortedKeys` + `.prettyPrinted`：输出要稳定，否则 B6 的金样本比对
/// 会因为字典序抖动而假红，用户手改过的文件也会在每次保存后产生无意义的 diff。
public struct Store: Sendable {

  public enum Failure: Error, Equatable {
    case unreadable(path: String)
    case malformed(path: String, detail: String)
    case unwritable(path: String, detail: String)
  }

  public static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }

  public static func makeDecoder() -> JSONDecoder {
    JSONDecoder()
  }

  private let fileSystem: any FileSystem
  private let directory: String

  public init(fileSystem: any FileSystem, directory: String) {
    self.fileSystem = fileSystem
    self.directory = directory
  }

  public var rulesPath: String { directory + "/rules.json" }
  public var settingsPath: String { directory + "/settings.json" }
  public var historyPath: String { directory + "/history.json" }
  public var activityPath: String { directory + "/activity.json" }
  public var activityStatisticsPath: String { directory + "/activity-statistics.json" }

  /// 读规则。文件不存在时写入内置预设再返回 —— 首次运行就是这条路径（decisions.md D5）。
  public func loadRuleSet() throws -> RuleSet {
    guard fileSystem.fileExists(atPath: rulesPath) else {
      let seeded = BuiltinRules.defaultRuleSet()
      try save(ruleSet: seeded)
      return seeded
    }
    var decoded = try decode(RuleSet.self, atPath: rulesPath)
    let enabledByID = Dictionary(
      uniqueKeysWithValues: decoded.rules
        .filter { RuleCatalog.isBuiltin($0.id) }
        .map { ($0.id, $0.enabled) }
    )
    let savedBuiltins = Dictionary(
      uniqueKeysWithValues: decoded.rules
        .filter { RuleCatalog.isBuiltin($0.id) }
        .map { ($0.id, $0) }
    )
    let builtins = BuiltinRules.defaultRuleSet().rules.map { rule in
      var current = rule
      current.enabled = enabledByID[rule.id] ?? rule.enabled
      if decoded.version >= RuleSet.currentVersion,
        let saved = savedBuiltins[rule.id]
      {
        current.actions = saved.actions
      }
      return current
    }
    let custom = decoded.rules.filter { !RuleCatalog.isBuiltin($0.id) }
    let normalized = RuleSet(version: RuleSet.currentVersion, rules: builtins + custom)
    if decoded.version < RuleSet.currentVersion || normalized != decoded {
      decoded = normalized
      try save(ruleSet: decoded)
    }
    return decoded
  }

  public func save(ruleSet: RuleSet) throws {
    try write(ruleSet, toPath: rulesPath)
  }

  public func loadSettings() throws -> Settings {
    guard fileSystem.fileExists(atPath: settingsPath) else {
      try save(settings: .default)
      return .default
    }
    var decoded = try decode(Settings.self, atPath: settingsPath)
    if decoded.version < Settings.currentVersion {
      decoded.version = Settings.currentVersion
      try save(settings: decoded)
    }
    return decoded
  }

  public func save(settings: Settings) throws {
    try write(settings, toPath: settingsPath)
  }

  public func loadHistory() throws -> History {
    guard fileSystem.fileExists(atPath: historyPath) else { return History(entries: []) }
    return try decode(History.self, atPath: historyPath)
  }

  public func save(history: History) throws {
    try write(history, toPath: historyPath)
  }

  public func loadActivity() throws -> ActivityLedger {
    guard fileSystem.fileExists(atPath: activityPath) else { return ActivityLedger() }
    return try decode(ActivityLedger.self, atPath: activityPath)
  }

  public func save(activity: ActivityLedger) throws {
    try write(activity, toPath: activityPath)
  }

  /// First launch after the statistics feature ships imports the retained safe activity
  /// projection once. From then on the aggregate file is authoritative and never follows
  /// the raw activity retention limit.
  public func loadActivityStatistics(
    seedEntries: [ActivityEntry] = [],
    calendar: Calendar
  ) throws -> ActivityStatistics {
    guard fileSystem.fileExists(atPath: activityStatisticsPath) else {
      var seeded = ActivityStatistics()
      seeded.record(contentsOf: seedEntries, calendar: calendar)
      try save(activityStatistics: seeded)
      return seeded
    }
    return try decode(ActivityStatistics.self, atPath: activityStatisticsPath)
  }

  public func save(activityStatistics: ActivityStatistics) throws {
    try write(activityStatistics, toPath: activityStatisticsPath)
  }

  private func decode<T: Decodable>(_ type: T.Type, atPath path: String) throws -> T {
    guard let data = try? fileSystem.read(atPath: path) else {
      throw Failure.unreadable(path: path)
    }
    do {
      return try Self.makeDecoder().decode(type, from: data)
    } catch {
      throw Failure.malformed(path: path, detail: String(describing: error))
    }
  }

  private func write<T: Encodable>(_ value: T, toPath path: String) throws {
    do {
      try fileSystem.createDirectory(atPath: directory)
      try fileSystem.write(try Self.makeEncoder().encode(value), toPath: path)
    } catch {
      throw Failure.unwritable(path: path, detail: String(describing: error))
    }
  }
}
