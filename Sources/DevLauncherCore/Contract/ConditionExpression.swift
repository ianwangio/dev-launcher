import Foundation

public indirect enum ConditionExpression: Codable, Equatable, Sendable, Identifiable {
  case group(ConditionGroup)
  case predicate(ConditionPredicate)

  public var id: UUID {
    switch self {
    case .group(let group): group.id
    case .predicate(let predicate): predicate.id
    }
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case group
    case predicate
  }

  private enum Kind: String, Codable {
    case group
    case predicate
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .type) {
    case .group:
      self = .group(try container.decode(ConditionGroup.self, forKey: .group))
    case .predicate:
      self = .predicate(try container.decode(ConditionPredicate.self, forKey: .predicate))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .group(let group):
      try container.encode(Kind.group, forKey: .type)
      try container.encode(group, forKey: .group)
    case .predicate(let predicate):
      try container.encode(Kind.predicate, forKey: .type)
      try container.encode(predicate, forKey: .predicate)
    }
  }

  public static func regularExpression(
    _ pattern: String,
    caseInsensitive: Bool = false,
    requiresExistingPath: Bool = false
  ) -> ConditionExpression {
    let regex = ConditionExpression.predicate(
      ConditionPredicate(
        field: .text,
        operation: .matchesRegularExpression,
        value: pattern,
        caseInsensitive: caseInsensitive
      )
    )
    guard requiresExistingPath else { return regex }
    return .group(
      ConditionGroup(
        combinator: .all,
        children: [
          regex,
          .predicate(ConditionPredicate(field: .fileExists, operation: .isTrue, value: "true")),
        ]
      )
    )
  }

  public var displaySummary: String {
    switch self {
    case .predicate(let predicate): return predicate.displaySummary
    case .group(let group):
      let separator = group.combinator == .all ? " AND " : " OR "
      return group.children.map { "(\($0.displaySummary))" }.joined(separator: separator)
    }
  }

  public var firstRegularExpression: ConditionPredicate? {
    switch self {
    case .predicate(let predicate):
      return predicate.operation == .matchesRegularExpression ? predicate : nil
    case .group(let group):
      return group.children.lazy.compactMap(\.firstRegularExpression).first
    }
  }

  public var containsFileExistenceRequirement: Bool {
    switch self {
    case .predicate(let predicate): predicate.field == .fileExists && predicate.operation == .isTrue
    case .group(let group): group.children.contains(where: \.containsFileExistenceRequirement)
    }
  }

  public var containsDirectoryRequirement: Bool {
    switch self {
    case .predicate(let predicate):
      return predicate.field == .fileKind
        && predicate.operation == .equals
        && predicate.value.localizedCaseInsensitiveCompare("directory") == .orderedSame
    case .group(let group):
      return group.children.contains(where: \.containsDirectoryRequirement)
    }
  }
}

public struct ConditionGroup: Codable, Equatable, Sendable, Identifiable {
  public var id: UUID
  public var combinator: ConditionCombinator
  public var children: [ConditionExpression]

  public init(id: UUID = UUID(), combinator: ConditionCombinator, children: [ConditionExpression]) {
    self.id = id
    self.combinator = combinator
    self.children = children
  }
}

public enum ConditionCombinator: String, Codable, CaseIterable, Equatable, Sendable {
  case all
  case any

  public var title: String {
    switch self {
    case .all: "满足全部 AND"
    case .any: "满足任一 OR"
    }
  }
}

public struct ConditionPredicate: Codable, Equatable, Sendable, Identifiable {
  public var id: UUID
  public var field: ConditionField
  public var operation: ConditionOperation
  public var value: String
  public var caseInsensitive: Bool
  public var captureName: String?

  public init(
    id: UUID = UUID(),
    field: ConditionField,
    operation: ConditionOperation,
    value: String,
    caseInsensitive: Bool = false,
    captureName: String? = nil
  ) {
    self.id = id
    self.field = field
    self.operation = operation
    self.value = value
    self.caseInsensitive = caseInsensitive
    self.captureName = captureName
  }

  public var displaySummary: String {
    if operation == .isTrue { return "\(field.title)" }
    return "\(field.title) \(operation.title) \(value)"
  }
}

public enum ConditionField: String, Codable, CaseIterable, Equatable, Sendable {
  case contentType
  case text
  case urlScheme
  case urlHost
  case urlPath
  case urlQuery
  case fileExists
  case fileKind
  case fileExtension
  case sourceApplication

  public var title: String {
    switch self {
    case .contentType: "内容类型"
    case .text: "文本"
    case .urlScheme: "URL Scheme"
    case .urlHost: "URL Host"
    case .urlPath: "URL 路径"
    case .urlQuery: "URL 查询"
    case .fileExists: "文件存在"
    case .fileKind: "文件类型"
    case .fileExtension: "文件扩展名"
    case .sourceApplication: "来源应用"
    }
  }

  public var defaultOperation: ConditionOperation {
    switch self {
    case .fileExists: .isTrue
    case .text: .contains
    default: .equals
    }
  }
}

public enum ConditionOperation: String, Codable, CaseIterable, Equatable, Sendable {
  case equals
  case contains
  case beginsWith
  case endsWith
  case matchesRegularExpression
  case isTrue

  public var title: String {
    switch self {
    case .equals: "是"
    case .contains: "包含"
    case .beginsWith: "开头是"
    case .endsWith: "结尾是"
    case .matchesRegularExpression: "匹配正则"
    case .isTrue: "为真"
    }
  }
}

public enum ClipboardContentKind: String, Codable, CaseIterable, Equatable, Sendable {
  case plainText
  case url
  case file
  case richText

  public var title: String {
    switch self {
    case .plainText: "纯文本"
    case .url: "网页链接"
    case .file: "文件或文件夹"
    case .richText: "富文本中的文本"
    }
  }
}

public struct NormalizedClipboard: Equatable, Sendable {
  public var text: String
  public var kind: ClipboardContentKind
  public var sourceBundleIdentifier: String?
  public var fileExists: Bool?
  public var fileKind: String?

  public init(
    text: String,
    kind: ClipboardContentKind = .plainText,
    sourceBundleIdentifier: String? = nil,
    fileExists: Bool? = nil,
    fileKind: String? = nil
  ) {
    self.text = text
    self.kind = kind
    self.sourceBundleIdentifier = sourceBundleIdentifier
    self.fileExists = fileExists
    self.fileKind = fileKind
  }
}

public struct ConditionIssue: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case emptyGroup
    case groupTooLarge
    case tooDeep
    case missingValue
    case invalidRegularExpression
    case duplicateCaptureName
  }

  public var nodeID: UUID
  public var kind: Kind
  public var message: String

  public init(nodeID: UUID, kind: Kind, message: String) {
    self.nodeID = nodeID
    self.kind = kind
    self.message = message
  }
}

public struct MatchEvaluation: Equatable, Sendable {
  public var matches: Bool
  public var captures: [String]
  public var namedValues: [String: String]
  public var nodeResults: [UUID: Bool]

  public init(
    matches: Bool,
    captures: [String] = [],
    namedValues: [String: String] = [:],
    nodeResults: [UUID: Bool] = [:]
  ) {
    self.matches = matches
    self.captures = captures
    self.namedValues = namedValues
    self.nodeResults = nodeResults
  }
}
