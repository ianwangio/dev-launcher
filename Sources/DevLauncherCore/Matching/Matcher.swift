import Foundation

/// 一条规则在一段文本上的命中结果。
public struct MatchResult: Equatable, Sendable {
  public var rule: Rule
  /// 下标 0 是整段匹配，1..n 是捕获组。未参与匹配的组是空串。
  public var captures: [String]
  public var namedValues: [String: String]

  public init(rule: Rule, captures: [String], namedValues: [String: String] = [:]) {
    self.rule = rule
    self.captures = captures
    self.namedValues = namedValues
  }
}

/// 纯函数：文本 + 规则 → 命中结果。
///
/// 这里**不做任何副作用**：不查磁盘、不起进程、不打开任何东西。
/// decisions.md Q5 那条安全边界（点击之前不执行任何东西）是靠这个结构保证的，
/// 不是靠自觉 —— `Matcher` 连一个 Port 都不持有，没有能力产生副作用。
public enum Matcher {

  /// 规则的正则写错时的表现：跳过这条规则，不抛错、不影响别的规则。
  /// 编辑器里校验正则是规则编辑界面的事，运行期只管别把整个面板拖垮。
  public static func match(text: String, rules: [Rule]) -> [MatchResult] {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }

    return match(input: NormalizedClipboard(text: trimmed), rules: rules)
  }

  public static func match(input: NormalizedClipboard, rules: [Rule]) -> [MatchResult] {
    let trimmed = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }

    var results: [MatchResult] = []
    for rule in rules where rule.enabled {
      var normalized = input
      normalized.text = trimmed
      let evaluation = ConditionEngine.evaluate(rule.condition, against: normalized)
      guard evaluation.matches else { continue }
      results.append(
        MatchResult(
          rule: rule,
          captures: evaluation.captures.isEmpty ? [trimmed] : evaluation.captures,
          namedValues: evaluation.namedValues
        )
      )
    }

    return results
  }
}
