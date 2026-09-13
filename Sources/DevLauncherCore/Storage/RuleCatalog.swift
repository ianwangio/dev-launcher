import Foundation

public struct RuleValidation: Equatable, Sendable {
  public var conditionIssues: [ConditionIssue]
  public var actionMessages: [Int: String]
  public var nameMessage: String?

  public var isValid: Bool {
    conditionIssues.isEmpty && actionMessages.isEmpty && nameMessage == nil
  }
}

public enum RuleCatalogFailure: Error, Equatable {
  case ruleNotFound(String)
  case builtinIsReadOnly(String)
  case customRuleRequired(String)
  case invalidRule(RuleValidation)
}

public struct RuleCatalog: Sendable {
  public private(set) var ruleSet: RuleSet

  public init(ruleSet: RuleSet) {
    self.ruleSet = ruleSet
  }

  public func snapshot(searchText: String = "") -> RuleLibraryPresentation {
    RuleLibraryPresentation(ruleSet: ruleSet, searchText: searchText)
  }

  public func draft(for id: String) throws -> Rule {
    guard let rule = ruleSet.rules.first(where: { $0.id == id }) else {
      throw RuleCatalogFailure.ruleNotFound(id)
    }
    return rule
  }

  public static func isBuiltin(_ id: String) -> Bool {
    builtinIDs.contains(id)
  }

  public func validate(_ draft: Rule) -> RuleValidation {
    var actionMessages: [Int: String] = [:]
    for (index, action) in draft.actions.enumerated() {
      let result = ActionCatalog.validate(action)
      if !result.isValid { actionMessages[index] = result.message }
    }
    return RuleValidation(
      conditionIssues: ConditionEngine.validate(draft.condition),
      actionMessages: actionMessages,
      nameMessage: draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "请输入规则名称"
        : nil
    )
  }

  public mutating func save(_ draft: Rule) throws {
    guard !Self.isBuiltin(draft.id) else { throw RuleCatalogFailure.builtinIsReadOnly(draft.id) }
    let validation = validate(draft)
    guard validation.isValid else { throw RuleCatalogFailure.invalidRule(validation) }

    if let index = ruleSet.rules.firstIndex(where: { $0.id == draft.id }) {
      ruleSet.rules[index] = draft
    } else {
      ruleSet.rules.append(draft)
    }
    ruleSet.version = RuleSet.currentVersion
  }

  public mutating func setBuiltinEnabled(_ id: String, _ enabled: Bool) throws {
    guard Self.isBuiltin(id) else { throw RuleCatalogFailure.customRuleRequired(id) }
    guard let index = ruleSet.rules.firstIndex(where: { $0.id == id }) else {
      throw RuleCatalogFailure.ruleNotFound(id)
    }
    ruleSet.rules[index].enabled = enabled
  }

  public mutating func appendAction(_ action: Action, to id: String) throws {
    guard ActionCatalog.validate(action).isValid else {
      throw RuleCatalogFailure.invalidRule(
        RuleValidation(conditionIssues: [], actionMessages: [0: "动作配置无效"], nameMessage: nil)
      )
    }
    guard let index = ruleSet.rules.firstIndex(where: { $0.id == id }) else {
      throw RuleCatalogFailure.ruleNotFound(id)
    }
    ruleSet.rules[index].actions.append(action)
    ruleSet.version = RuleSet.currentVersion
  }

  public mutating func removeAction(at actionIndex: Int, from id: String) throws {
    guard let ruleIndex = ruleSet.rules.firstIndex(where: { $0.id == id }) else {
      throw RuleCatalogFailure.ruleNotFound(id)
    }
    guard ruleSet.rules[ruleIndex].actions.indices.contains(actionIndex) else {
      throw RuleCatalogFailure.ruleNotFound("\(id)#\(actionIndex)")
    }
    ruleSet.rules[ruleIndex].actions.remove(at: actionIndex)
    ruleSet.version = RuleSet.currentVersion
  }

  public mutating func restoreBuiltinActions(_ id: String) throws {
    guard Self.isBuiltin(id) else { throw RuleCatalogFailure.customRuleRequired(id) }
    guard let defaults = BuiltinRules.defaultRuleSet().rules.first(where: { $0.id == id }),
      let index = ruleSet.rules.firstIndex(where: { $0.id == id })
    else { throw RuleCatalogFailure.ruleNotFound(id) }
    ruleSet.rules[index].actions = defaults.actions
    ruleSet.version = RuleSet.currentVersion
  }

  public mutating func duplicateAsCustom(_ id: String) throws -> String {
    guard var copy = ruleSet.rules.first(where: { $0.id == id }) else {
      throw RuleCatalogFailure.ruleNotFound(id)
    }
    let newID = "custom.\(UUID().uuidString.lowercased())"
    copy.id = newID
    copy.name += " 副本"
    copy.enabled = false
    ruleSet.rules.append(copy)
    return newID
  }

  public mutating func createCustom() -> String {
    let id = "custom.\(UUID().uuidString.lowercased())"
    ruleSet.rules.append(
      Rule(
        id: id,
        name: "新建规则",
        enabled: false,
        condition: .group(
          ConditionGroup(
            combinator: .all,
            children: [
              .predicate(
                ConditionPredicate(
                  field: .text,
                  operation: .matchesRegularExpression,
                  value: ".*"
                )
              )
            ]
          )
        ),
        actions: [ActionCatalog.defaultAction(for: .openURL)]
      )
    )
    return id
  }

  public mutating func deleteCustom(_ id: String) throws {
    guard !Self.isBuiltin(id) else { throw RuleCatalogFailure.builtinIsReadOnly(id) }
    guard let index = ruleSet.rules.firstIndex(where: { $0.id == id }) else {
      throw RuleCatalogFailure.ruleNotFound(id)
    }
    ruleSet.rules.remove(at: index)
  }

  public mutating func reorderCustom(_ ids: [String]) throws {
    let existing = ruleSet.rules.filter { !Self.isBuiltin($0.id) }
    guard Set(ids) == Set(existing.map(\.id)) else {
      throw RuleCatalogFailure.customRuleRequired("排序列表必须包含全部自定义规则")
    }
    let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
    let builtins = ruleSet.rules.filter { Self.isBuiltin($0.id) }
    ruleSet.rules = builtins + ids.compactMap { byID[$0] }
  }

  private static let builtinIDs: Set<String> = [
    "builtin.local-path",
    "builtin.linear-issue",
    "builtin.github-issue-number",
  ]
}
