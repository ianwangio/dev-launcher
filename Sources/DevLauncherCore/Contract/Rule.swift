import Foundation

public struct Rule: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var name: String
  public var enabled: Bool
  public var condition: ConditionExpression
  public var actions: [Action]

  public init(
    id: String,
    name: String,
    enabled: Bool = true,
    condition: ConditionExpression,
    actions: [Action]
  ) {
    self.id = id
    self.name = name
    self.enabled = enabled
    self.condition = condition
    self.actions = actions
  }

  /// v1-compatible construction surface. New code should pass `condition`.
  public init(
    id: String,
    name: String,
    enabled: Bool = true,
    pattern: String,
    caseInsensitive: Bool = false,
    requiresExistingPath: Bool = false,
    actions: [Action]
  ) {
    self.init(
      id: id,
      name: name,
      enabled: enabled,
      condition: .regularExpression(
        pattern,
        caseInsensitive: caseInsensitive,
        requiresExistingPath: requiresExistingPath
      ),
      actions: actions
    )
  }

  /// Compatibility projections used by the existing runtime until the v2 editor owns every caller.
  public var pattern: String { condition.firstRegularExpression?.value ?? condition.displaySummary }
  public var caseInsensitive: Bool { condition.firstRegularExpression?.caseInsensitive ?? false }
  public var requiresExistingPath: Bool { condition.containsFileExistenceRequirement }
  public var requiresExistingDirectory: Bool { condition.containsDirectoryRequirement }

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case enabled
    case condition
    case actions
    case pattern
    case caseInsensitive
    case requiresExistingPath
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    actions = try container.decode([Action].self, forKey: .actions)

    if let condition = try container.decodeIfPresent(ConditionExpression.self, forKey: .condition) {
      self.condition = condition
    } else {
      self.condition = .regularExpression(
        try container.decode(String.self, forKey: .pattern),
        caseInsensitive: try container.decodeIfPresent(Bool.self, forKey: .caseInsensitive)
          ?? false,
        requiresExistingPath: try container.decodeIfPresent(
          Bool.self, forKey: .requiresExistingPath) ?? false
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(enabled, forKey: .enabled)
    try container.encode(condition, forKey: .condition)
    try container.encode(actions, forKey: .actions)
  }
}

public struct RuleSet: Codable, Equatable, Sendable {
  public static let currentVersion = 3

  public var version: Int
  public var rules: [Rule]

  public init(version: Int = RuleSet.currentVersion, rules: [Rule]) {
    self.version = version
    self.rules = rules
  }
}
