import Foundation

public enum ActivityStatus: String, Codable, Equatable, Sendable {
  case succeeded
  case failed
}

/// 日常活动的安全投影。这里刻意没有剪贴板内容、URL、参数、输出或凭据字段。
public struct ActivityEntry: Codable, Equatable, Sendable, Identifiable {
  public var id: UUID
  public var ruleID: String
  public var ruleName: String
  public var actionTitle: String
  public var status: ActivityStatus
  public var occurredAt: Date

  public init(
    id: UUID = UUID(),
    ruleID: String,
    ruleName: String,
    actionTitle: String,
    status: ActivityStatus,
    occurredAt: Date
  ) {
    self.id = id
    self.ruleID = ruleID
    self.ruleName = ruleName
    self.actionTitle = actionTitle
    self.status = status
    self.occurredAt = occurredAt
  }
}

public struct ActivityLedger: Codable, Equatable, Sendable {
  public static let supportedRetentionLimits = [100, 500, 1000, 2000, 5000]
  public static let defaultRetentionLimit = 1000
  public static let maximumRetentionLimit = 5000
  public private(set) var entries: [ActivityEntry]

  public init(
    entries: [ActivityEntry] = [],
    retentionLimit: Int = ActivityLedger.defaultRetentionLimit
  ) {
    self.entries = Array(entries.suffix(Self.validStorageLimit(retentionLimit)))
  }

  public mutating func append(
    _ entry: ActivityEntry,
    retentionLimit: Int = ActivityLedger.defaultRetentionLimit
  ) {
    entries.append(entry)
    trim(to: retentionLimit)
  }

  public mutating func trim(to retentionLimit: Int) {
    let limit = Self.validStorageLimit(retentionLimit)
    if entries.count > limit { entries.removeFirst(entries.count - limit) }
  }

  public mutating func clear() {
    entries.removeAll()
  }

  private static func validStorageLimit(_ value: Int) -> Int {
    min(max(1, value), maximumRetentionLimit)
  }

  private enum CodingKeys: String, CodingKey {
    case entries
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let entries = try container.decodeIfPresent([ActivityEntry].self, forKey: .entries) ?? []
    self.entries = Array(entries.suffix(Self.maximumRetentionLimit))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(entries, forKey: .entries)
  }
}
