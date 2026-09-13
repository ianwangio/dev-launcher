import DevLauncherCore
import Testing

@Test("规则库把内置规则和自定义规则分开，并由 Core 给出权限")
func ruleLibrarySeparatesOriginsAndCapabilities() {
  let custom = Rule(
    id: "custom.project-link",
    name: "项目链接",
    pattern: #"^https://github.com/"#,
    actions: [.openURL(OpenURLAction(title: "在浏览器中打开", urlTemplate: "$0"))]
  )
  let library = RuleLibraryPresentation(
    ruleSet: RuleSet(rules: BuiltinRules.defaultRuleSet().rules + [custom])
  )

  #expect(
    library.builtin.map(\.id) == [
      "builtin.local-path",
      "builtin.linear-issue",
      "builtin.github-issue-number",
    ])
  #expect(library.custom.map(\.id) == ["custom.project-link"])
  #expect(library.builtin.allSatisfy { !$0.capabilities.canEdit && !$0.capabilities.canDelete })
  #expect(library.builtin.allSatisfy { $0.capabilities.canDuplicate })
  #expect(library.custom.allSatisfy { $0.capabilities.canEdit && $0.capabilities.canDelete })
}

@Test("规则搜索不改变内置与自定义的归属")
func ruleLibrarySearchPreservesOrigin() {
  let custom = Rule(id: "mine", name: "本地项目别名", pattern: "x", actions: [])
  let set = RuleSet(rules: BuiltinRules.defaultRuleSet().rules + [custom])
  let result = RuleLibraryPresentation(ruleSet: set, searchText: "本地")

  #expect(result.builtin.map(\.id) == ["builtin.local-path"])
  #expect(result.custom.map(\.id) == ["mine"])
}

@Test("规则详情只暴露友好动作摘要，不投影完整 URL 和命令参数")
func rulePresentationKeepsTechnicalDetailsOutOfSummary() {
  let item = RulePresentation.project(BuiltinRules.localPath)

  #expect(
    item.actionTitles == [
      "在 Finder 中显示",
      "在 iTerm2 中打开",
      "Claude Code 终端",
      "Claude Code 桌面",
      "Codex 桌面",
    ])
  #expect(
    item.actionIcons == [
      .application(name: "Finder"),
      .application(name: "iTerm2"),
      .application(name: "Terminal"),
      .application(name: "Claude"),
      .application(name: "Codex"),
    ])
  #expect(item.subtitle.contains("claude-cli://") == false)
  #expect(item.shortContext == "本地文件夹")
}

@Test("自定义规则图标按条件和动作自动推导")
func rulePresentationInfersSemanticIcons() {
  let web = Rule(
    id: "custom.web",
    name: "网页",
    pattern: "x",
    actions: [.openURL(OpenURLAction(title: "打开", urlTemplate: "https://example.com/$0"))]
  )
  let script = Rule(
    id: "custom.script",
    name: "脚本",
    pattern: "x",
    actions: [.runScript(RunScriptAction(title: "运行", scriptPath: "/tmp/a.py", args: []))]
  )
  let app = Rule(
    id: "custom.app",
    name: "应用",
    pattern: "x",
    actions: [
      .openWithApplication(
        OpenWithApplicationAction(title: "打开", applicationName: "Codex", targetTemplate: "$0")
      )
    ]
  )
  let templatedWeb = Rule(
    id: "custom.templated-web",
    name: "模板网页",
    pattern: "x",
    actions: [.openURL(OpenURLAction(title: "打开", urlTemplate: "$0"))]
  )

  #expect(RulePresentation.project(web).icon == .web)
  #expect(RulePresentation.project(script).icon == .script)
  #expect(RulePresentation.project(app).icon == .application(name: "Codex"))
  #expect(RulePresentation.project(templatedWeb).icon == .web)
}
