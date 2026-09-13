import Foundation

public enum ActivityStatisticsGranularity: String, Codable, Equatable, Sendable {
  case day
  case month
}

public struct ActivityStatisticsRanking: Codable, Equatable, Sendable, Identifiable {
  public var name: String
  public var count: Int
  public var id: String { name }

  public init(name: String, count: Int) {
    self.name = name
    self.count = count
  }
}

/// A count-only projection of activity. It deliberately excludes clipboard content,
/// resolved targets, command arguments, process output, and credentials.
public struct ActivityStatisticsBucket: Codable, Equatable, Sendable, Identifiable {
  public var start: Date
  public private(set) var succeededCount: Int
  public private(set) var failedCount: Int
  public private(set) var ruleCounts: [String: Int]
  public private(set) var actionCounts: [String: Int]

  public var id: Date { start }
  public var totalCount: Int { succeededCount + failedCount }
  public var successRate: Double {
    guard totalCount > 0 else { return 0 }
    return Double(succeededCount) / Double(totalCount)
  }
  public var rankedRules: [ActivityStatisticsRanking] { Self.ranking(ruleCounts) }
  public var rankedActions: [ActivityStatisticsRanking] { Self.ranking(actionCounts) }

  public init(
    start: Date,
    succeededCount: Int = 0,
    failedCount: Int = 0,
    ruleCounts: [String: Int] = [:],
    actionCounts: [String: Int] = [:]
  ) {
    self.start = start
    self.succeededCount = succeededCount
    self.failedCount = failedCount
    self.ruleCounts = ruleCounts
    self.actionCounts = actionCounts
  }

  fileprivate mutating func record(_ entry: ActivityEntry) {
    switch entry.status {
    case .succeeded: succeededCount += 1
    case .failed: failedCount += 1
    }
    ruleCounts[entry.ruleName, default: 0] += 1
    actionCounts[entry.actionTitle, default: 0] += 1
  }

  fileprivate mutating func merge(_ other: ActivityStatisticsBucket) {
    succeededCount += other.succeededCount
    failedCount += other.failedCount
    for (name, count) in other.ruleCounts { ruleCounts[name, default: 0] += count }
    for (name, count) in other.actionCounts { actionCounts[name, default: 0] += count }
  }

  fileprivate mutating func collapseSlashActionNames(to actionTitle: String) {
    let legacyNames = actionCounts.keys.filter { $0.contains("/") }
    let count = legacyNames.reduce(0) { $0 + (actionCounts[$1] ?? 0) }
    for name in legacyNames { actionCounts.removeValue(forKey: name) }
    if count > 0 { actionCounts[actionTitle, default: 0] += count }
  }

  private static func ranking(_ counts: [String: Int]) -> [ActivityStatisticsRanking] {
    counts
      .map(ActivityStatisticsRanking.init)
      .sorted { lhs, rhs in
        lhs.count == rhs.count ? lhs.name < rhs.name : lhs.count > rhs.count
      }
  }
}

public struct ActivityStatistics: Codable, Equatable, Sendable {
  public static let currentVersion = 2
  private var version: Int
  public private(set) var days: [ActivityStatisticsBucket]

  public init(days: [ActivityStatisticsBucket] = []) {
    self.version = Self.currentVersion
    self.days = days.sorted { $0.start > $1.start }
  }

  /// The unreleased v1 prototype recorded a repository candidate's concrete
  /// `owner/repo` label as an action name. Collapse those labels back to the rule's
  /// action title once, then persist v2 so custom slash-containing titles remain intact.
  @discardableResult
  public mutating func migrateLegacyRepositoryActionTitles(to actionTitle: String) -> Bool {
    guard version < Self.currentVersion else { return false }
    for index in days.indices {
      days[index].collapseSlashActionNames(to: actionTitle)
    }
    version = Self.currentVersion
    return true
  }

  private enum CodingKeys: String, CodingKey {
    case version
    case days
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    days = try container.decodeIfPresent([ActivityStatisticsBucket].self, forKey: .days) ?? []
    days.sort { $0.start > $1.start }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(version, forKey: .version)
    try container.encode(days, forKey: .days)
  }

  public mutating func record(_ entry: ActivityEntry, calendar: Calendar) {
    let start = calendar.startOfDay(for: entry.occurredAt)
    if let index = days.firstIndex(where: { calendar.isDate($0.start, inSameDayAs: start) }) {
      days[index].record(entry)
    } else {
      var bucket = ActivityStatisticsBucket(start: start)
      bucket.record(entry)
      days.append(bucket)
      days.sort { $0.start > $1.start }
    }
  }

  public mutating func record(contentsOf entries: [ActivityEntry], calendar: Calendar) {
    for entry in entries { record(entry, calendar: calendar) }
  }

  public func buckets(
    granularity: ActivityStatisticsGranularity,
    year: Int,
    calendar: Calendar
  ) -> [ActivityStatisticsBucket] {
    let matchingDays = days.filter { calendar.component(.year, from: $0.start) == year }
    guard granularity == .month else { return matchingDays.sorted { $0.start > $1.start } }

    var grouped: [Date: ActivityStatisticsBucket] = [:]
    for day in matchingDays {
      let components = calendar.dateComponents([.year, .month], from: day.start)
      guard let monthStart = calendar.date(from: components) else { continue }
      var month = grouped[monthStart] ?? ActivityStatisticsBucket(start: monthStart)
      month.merge(day)
      grouped[monthStart] = month
    }
    return grouped.values.sorted { $0.start > $1.start }
  }

  public func summary(
    from start: Date = .distantPast,
    through end: Date = .distantFuture,
    calendar: Calendar
  ) -> ActivityStatisticsBucket {
    _ = calendar
    var result = ActivityStatisticsBucket(start: start)
    for day in days where day.start >= start && day.start <= end { result.merge(day) }
    return result
  }

  public func availableYears(calendar: Calendar) -> [Int] {
    Set(days.map { calendar.component(.year, from: $0.start) }).sorted(by: >)
  }
}
