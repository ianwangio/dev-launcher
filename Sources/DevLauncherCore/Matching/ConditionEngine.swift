import Foundation

public enum ConditionEngine {
  public static let maximumDepth = 3
  public static let maximumChildrenPerGroup = 10

  public static func evaluate(
    _ expression: ConditionExpression,
    against input: NormalizedClipboard
  ) -> MatchEvaluation {
    evaluate(expression, against: input, depth: 1)
  }

  public static func validate(_ expression: ConditionExpression) -> [ConditionIssue] {
    var issues: [ConditionIssue] = []
    var captureOwners: [String: UUID] = [:]
    validate(expression, depth: 1, issues: &issues, captureOwners: &captureOwners)
    return issues
  }

  public static func advisory(for predicate: ConditionPredicate) -> String? {
    guard predicate.operation != .matchesRegularExpression else { return nil }
    let value = predicate.value
    let looksLikeRegularExpression =
      value == ".*" || value.hasPrefix("^") || value.hasSuffix("$")
      || value.contains("\\d") || value.contains("[") || value.contains("]")
    guard looksLikeRegularExpression else { return nil }
    return "当前比较会按字面文本处理；如需通配，请选择“匹配正则”"
  }

  private static func evaluate(
    _ expression: ConditionExpression,
    against input: NormalizedClipboard,
    depth: Int
  ) -> MatchEvaluation {
    switch expression {
    case .predicate(let predicate):
      return evaluate(predicate, against: input)

    case .group(let group):
      let childResults = group.children.map { evaluate($0, against: input, depth: depth + 1) }
      let matches: Bool
      switch group.combinator {
      case .all: matches = !childResults.isEmpty && childResults.allSatisfy(\.matches)
      case .any: matches = childResults.contains(where: \.matches)
      }

      let contributing = group.combinator == .all ? childResults : childResults.filter(\.matches)
      var captures = [input.text]
      var namedValues: [String: String] = [:]
      var nodeResults: [UUID: Bool] = [group.id: matches]
      for result in contributing where result.matches {
        if result.captures.count > captures.count { captures = result.captures }
        namedValues.merge(result.namedValues) { current, _ in current }
      }
      for result in childResults {
        nodeResults.merge(result.nodeResults) { _, child in child }
      }
      return MatchEvaluation(
        matches: matches,
        captures: captures,
        namedValues: namedValues,
        nodeResults: nodeResults
      )
    }
  }

  private static func evaluate(
    _ predicate: ConditionPredicate,
    against input: NormalizedClipboard
  ) -> MatchEvaluation {
    let candidate = fieldValue(predicate.field, input: input)
    var captures = [input.text]
    let matches: Bool

    switch predicate.operation {
    case .isTrue:
      // nil means a read-only fact is intentionally deferred to ActionResolver.
      matches = candidate == nil || candidate == "true"
    case .matchesRegularExpression:
      var options: NSRegularExpression.Options = []
      if predicate.caseInsensitive { options.insert(.caseInsensitive) }
      if let regex = try? NSRegularExpression(pattern: predicate.value, options: options) {
        let text = candidate ?? ""
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = regex.firstMatch(in: text, range: range) {
          captures = (0..<match.numberOfRanges).map { index in
            guard let swiftRange = Range(match.range(at: index), in: text) else { return "" }
            return String(text[swiftRange])
          }
          matches = true
        } else {
          matches = false
        }
      } else {
        matches = false
      }
    case .equals, .contains, .beginsWith, .endsWith:
      // 文件系统事实可能在纯文本复制阶段尚不可用；匹配阶段保持纯函数，
      // 最终由 ActionResolver 通过 FileSystem Port 验证后再生成候选项。
      if candidate == nil && (predicate.field == .fileExists || predicate.field == .fileKind) {
        matches = true
        break
      }
      guard let candidate else {
        matches = false
        break
      }
      matches = compare(
        candidate, predicate.value, operation: predicate.operation,
        insensitive: predicate.caseInsensitive)
    }

    let namedValues: [String: String]
    if matches, let name = predicate.captureName, !name.isEmpty {
      namedValues = [name: captures.first ?? candidate ?? ""]
    } else {
      namedValues = [:]
    }
    return MatchEvaluation(
      matches: matches,
      captures: captures,
      namedValues: namedValues,
      nodeResults: [predicate.id: matches]
    )
  }

  private static func fieldValue(_ field: ConditionField, input: NormalizedClipboard) -> String? {
    switch field {
    case .contentType: return input.kind.rawValue
    case .text: return input.text
    case .sourceApplication: return input.sourceBundleIdentifier
    case .fileExists: return input.fileExists.map(String.init)
    case .fileKind: return input.fileKind
    case .fileExtension: return (input.text as NSString).pathExtension
    case .urlScheme: return URLComponents(string: input.text)?.scheme
    case .urlHost: return URLComponents(string: input.text)?.host
    case .urlPath: return URLComponents(string: input.text)?.path
    case .urlQuery: return URLComponents(string: input.text)?.query
    }
  }

  private static func compare(
    _ lhs: String,
    _ rhs: String,
    operation: ConditionOperation,
    insensitive: Bool
  ) -> Bool {
    let a = insensitive ? lhs.lowercased() : lhs
    let b = insensitive ? rhs.lowercased() : rhs
    switch operation {
    case .equals: return a == b
    case .contains: return a.contains(b)
    case .beginsWith: return a.hasPrefix(b)
    case .endsWith: return a.hasSuffix(b)
    case .matchesRegularExpression, .isTrue: return false
    }
  }

  private static func validate(
    _ expression: ConditionExpression,
    depth: Int,
    issues: inout [ConditionIssue],
    captureOwners: inout [String: UUID]
  ) {
    if depth > maximumDepth {
      issues.append(ConditionIssue(nodeID: expression.id, kind: .tooDeep, message: "条件组最多嵌套三层"))
    }

    switch expression {
    case .group(let group):
      if group.children.isEmpty {
        issues.append(ConditionIssue(nodeID: group.id, kind: .emptyGroup, message: "条件组至少需要一个条件"))
      }
      if group.children.count > maximumChildrenPerGroup {
        issues.append(ConditionIssue(nodeID: group.id, kind: .groupTooLarge, message: "每组最多十个条件"))
      }
      for child in group.children {
        validate(child, depth: depth + 1, issues: &issues, captureOwners: &captureOwners)
      }

    case .predicate(let predicate):
      if predicate.operation != .isTrue && predicate.value.isEmpty {
        issues.append(ConditionIssue(nodeID: predicate.id, kind: .missingValue, message: "请输入匹配值"))
      }
      if predicate.operation == .matchesRegularExpression,
        (try? NSRegularExpression(pattern: predicate.value)) == nil
      {
        issues.append(
          ConditionIssue(nodeID: predicate.id, kind: .invalidRegularExpression, message: "正则表达式无效"))
      }
      if let name = predicate.captureName, !name.isEmpty {
        if captureOwners[name] != nil {
          issues.append(
            ConditionIssue(nodeID: predicate.id, kind: .duplicateCaptureName, message: "捕获名称必须唯一"))
        } else {
          captureOwners[name] = predicate.id
        }
      }
    }
  }
}
