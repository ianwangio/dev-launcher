import DevLauncherCore
import Foundation
import Testing

@Test("AND 与嵌套 OR 条件树返回逐节点结果")
func compoundConditionsEvaluate() {
  let host = ConditionPredicate(field: .urlHost, operation: .equals, value: "github.com")
  let issue = ConditionPredicate(field: .urlPath, operation: .contains, value: "/issues/")
  let pull = ConditionPredicate(field: .urlPath, operation: .contains, value: "/pull/")
  let expression = ConditionExpression.group(
    ConditionGroup(
      combinator: .all,
      children: [
        .predicate(host),
        .group(ConditionGroup(combinator: .any, children: [.predicate(issue), .predicate(pull)])),
      ]
    )
  )

  let issueResult = ConditionEngine.evaluate(
    expression,
    against: NormalizedClipboard(text: "https://github.com/openai/codex/issues/42", kind: .url)
  )
  let miss = ConditionEngine.evaluate(
    expression,
    against: NormalizedClipboard(text: "https://github.com/openai/codex/tree/main", kind: .url)
  )

  #expect(issueResult.matches)
  #expect(issueResult.nodeResults[host.id] == true)
  #expect(issueResult.nodeResults[issue.id] == true)
  #expect(issueResult.nodeResults[pull.id] == false)
  #expect(!miss.matches)
}

@Test("条件验证拒绝超过三层、空值、坏正则和重复捕获名")
func conditionValidationExplainsEveryProblem() {
  let first = ConditionPredicate(
    field: .text,
    operation: .matchesRegularExpression,
    value: "([",
    captureName: "value"
  )
  let second = ConditionPredicate(
    field: .text,
    operation: .contains,
    value: "",
    captureName: "value"
  )
  let tooDeep = ConditionExpression.group(
    ConditionGroup(
      combinator: .all,
      children: [
        .group(
          ConditionGroup(
            combinator: .all,
            children: [
              .group(
                ConditionGroup(
                  combinator: .all,
                  children: [
                    .group(ConditionGroup(combinator: .all, children: [.predicate(first)]))
                  ]
                )
              )
            ]
          )
        ),
        .predicate(second),
      ]
    )
  )
  let kinds = Set(ConditionEngine.validate(tooDeep).map(\.kind))

  #expect(kinds.contains(.tooDeep))
  #expect(kinds.contains(.invalidRegularExpression))
  #expect(kinds.contains(.missingValue))
  #expect(kinds.contains(.duplicateCaptureName))
}

@Test("URL、文件与来源应用条件使用归一化输入")
func semanticPredicatesUseNormalizedInput() {
  let input = NormalizedClipboard(
    text: "/Users/chen/Devel/demo.swift",
    kind: .file,
    sourceBundleIdentifier: "com.apple.finder",
    fileExists: true,
    fileKind: "file"
  )
  let expression = ConditionExpression.group(
    ConditionGroup(
      combinator: .all,
      children: [
        .predicate(ConditionPredicate(field: .contentType, operation: .equals, value: "file")),
        .predicate(ConditionPredicate(field: .fileExists, operation: .isTrue, value: "true")),
        .predicate(ConditionPredicate(field: .fileExtension, operation: .equals, value: "swift")),
        .predicate(
          ConditionPredicate(
            field: .sourceApplication, operation: .equals, value: "com.apple.finder")
        ),
      ]
    )
  )

  #expect(ConditionEngine.evaluate(expression, against: input).matches)
}

@Test("v1 rules.json 读取后原子投影为 v2 条件树")
func storeMigratesV1Rules() throws {
  let old = """
    {
      "version": 1,
      "rules": [{
        "id": "custom.old",
        "name": "旧规则",
        "enabled": true,
        "pattern": "^OLD-([0-9]+)$",
        "caseInsensitive": true,
        "requiresExistingPath": false,
        "actions": [{
          "type": "openURL",
          "title": "打开",
          "urlTemplate": "https://example.com/$0"
        }]
      }]
    }
    """
  let fs = FakeFileSystem(files: ["/support/rules.json": old])
  let store = Store(fileSystem: fs, directory: "/support")

  let migrated = try store.loadRuleSet()
  let written = try #require(fs.contents(at: "/support/rules.json"))
  let migratedCustom = try #require(migrated.rules.first { $0.id == "custom.old" })

  #expect(migrated.version == 3)
  #expect(migratedCustom.pattern == "^OLD-([0-9]+)$")
  #expect(Matcher.match(text: "old-7", rules: [migratedCustom]).count == 1)
  #expect(written.contains("\"condition\"") == true)
  #expect(written.contains("\"version\" : 3") == true)
  #expect(written.contains("\"pattern\"") == false)
}

@Test("加载时刷新内置定义，只保留启停状态和自定义规则")
func storeRefreshesBuiltinDefinitions() throws {
  var staleBuiltin = BuiltinRules.localPath
  staleBuiltin.enabled = false
  staleBuiltin.condition = .regularExpression(#"^(?:/|~/)[^\s]+$"#, requiresExistingPath: true)
  let custom = Rule(id: "custom.keep", name: "保留", pattern: "^keep$", actions: [])
  let stale = RuleSet(rules: [staleBuiltin, custom])
  let fs = FakeFileSystem()
  let store = Store(fileSystem: fs, directory: "/support")
  try store.save(ruleSet: stale)

  let loaded = try store.loadRuleSet()
  let builtin = try #require(loaded.rules.first { $0.id == "builtin.local-path" })

  #expect(builtin.enabled == false)
  #expect(builtin.pattern == #"^(?:/|~/).+$"#)
  #expect(loaded.rules.contains { $0.id == "custom.keep" })
}

@Test("RuleCatalog 强制内置只读，自定义规则可保存和删除")
func ruleCatalogEnforcesCapabilities() throws {
  var catalog = RuleCatalog(ruleSet: BuiltinRules.defaultRuleSet())
  #expect(throws: RuleCatalogFailure.self) { try catalog.deleteCustom("builtin.local-path") }
  #expect(throws: RuleCatalogFailure.self) { try catalog.save(BuiltinRules.localPath) }

  let copyID = try catalog.duplicateAsCustom("builtin.local-path")
  var copy = try catalog.draft(for: copyID)
  copy.name = "我的路径"
  try catalog.save(copy)
  #expect(catalog.snapshot().custom.map(\.name) == ["我的路径"])

  try catalog.deleteCustom(copyID)
  #expect(catalog.snapshot().custom.isEmpty)
}

@Test("内置规则动作可新增删除，保存后保留，也能恢复默认")
func builtinActionsCanBeCustomizedAndRestored() throws {
  var catalog = RuleCatalog(ruleSet: BuiltinRules.defaultRuleSet())
  try catalog.removeAction(at: 0, from: "builtin.local-path")
  try catalog.appendAction(
    ActionCatalog.templates.first { $0.id == "chrome" }!.action, to: "builtin.local-path")

  let fs = FakeFileSystem()
  let store = Store(fileSystem: fs, directory: "/support")
  try store.save(ruleSet: catalog.ruleSet)
  let reloaded = try store.loadRuleSet()
  let customized = try #require(reloaded.rules.first { $0.id == "builtin.local-path" })
  #expect(customized.actions.count == 5)
  #expect(customized.actions.last?.title == "在 Chrome 中打开")

  var restoredCatalog = RuleCatalog(ruleSet: reloaded)
  try restoredCatalog.restoreBuiltinActions("builtin.local-path")
  let restored = try #require(
    restoredCatalog.ruleSet.rules.first { $0.id == "builtin.local-path" }
  )
  #expect(restored.actions == BuiltinRules.localPath.actions)
}

@Test("指定应用动作按安装状态生成计划或置灰")
func applicationActionUsesAvailabilityAndPlan() {
  let (fs, runner) = Sample.environment()
  let availableApps = FakeApplicationOpener(available: ["Zed"])
  let resolver = ActionResolver(
    urlOpener: FakeURLOpener(handlers: [:]),
    fileSystem: fs,
    interpreters: InterpreterResolver(runner: runner, fileSystem: fs, loginShell: "/bin/zsh"),
    applicationOpener: availableApps
  )
  let rule = Rule(
    id: "custom.zed",
    name: "Zed",
    pattern: "^(.+)$",
    actions: [
      .openWithApplication(
        OpenWithApplicationAction(
          title: "在 Zed 中打开",
          applicationName: "Zed",
          targetTemplate: "{{匹配内容}}"
        )
      ),
      .openWithApplication(
        OpenWithApplicationAction(
          title: "在缺失应用中打开",
          applicationName: "Missing",
          targetTemplate: "{{匹配内容}}"
        )
      ),
    ]
  )
  let candidates = resolver.candidates(for: Matcher.match(text: "/tmp/project", rules: [rule]))

  #expect(
    candidates[0].plan
      == .openWithApplication(target: "/tmp/project", applicationName: "Zed")
  )
  #expect(candidates[1].plan == nil)
  #expect(candidates[1].availability.reason == "未找到应用 Missing")
}

@Test("动作目录按类型分组，并包含路径与浏览器应用模板")
func actionCatalogHasFinalShape() {
  #expect(ActionCatalog.descriptors.map(\.kind) == ActionKind.allCases)
  #expect(
    ActionCatalog.templates.map(\.id) == [
      "finder", "terminal", "iterm2", "claude-code", "codex", "zed", "browser", "chrome",
      "linear", "github",
    ])
  #expect(
    ActionCatalog.templates(in: .path).map(\.id) == [
      "finder", "terminal", "iterm2", "claude-code", "codex", "zed",
    ])
  #expect(ActionCatalog.templates(in: .url).map(\.id) == ["browser", "chrome", "linear"])
  #expect(
    ActionCatalog.preview(ActionCatalog.templates[4].action, values: ["匹配内容": "next.js"]).title
      == "在 Codex 中打开")
}

@Test("动作模板同时支持匹配内容和命名值令牌")
func namedTemplateValuesExpand() {
  let expanded = TemplateExpander.expand(
    "https://{{host}}/issues/$1?source={{匹配内容}}",
    captures: ["#42", "42"],
    namedValues: ["host": "github.com"],
    escaping: .percentEncoded
  )
  #expect(expanded == "https://github.com/issues/42?source=%2342")
}

@Test("字面比较不会把正则写法当通配，并给编辑器明确提示")
func literalComparisonWarnsAboutRegexLookingValue() {
  let predicate = ConditionPredicate(
    field: .urlScheme,
    operation: .equals,
    value: ".*"
  )
  let result = ConditionEngine.evaluate(
    .predicate(predicate),
    against: NormalizedClipboard(text: "https://github.com/openai/codex", kind: .url)
  )

  #expect(!result.matches)
  #expect(ConditionEngine.advisory(for: predicate)?.contains("字面文本") == true)
}
