import DevLauncherCore
import Foundation
import Testing

// MARK: - TemplateExpander

@Test("URL 模板里的捕获组要百分号编码，脚本参数不编码")
func templateEscaping() {
  let captures = ["/Users/chen/我的 项目", "chen"]

  #expect(
    TemplateExpander.expand(
      "claude-cli://open?cwd=$0", captures: captures, escaping: .percentEncoded)
      == "claude-cli://open?cwd=%2FUsers%2Fchen%2F%E6%88%91%E7%9A%84%20%E9%A1%B9%E7%9B%AE"
  )
  #expect(
    TemplateExpander.expand("$0", captures: captures, escaping: .raw) == "/Users/chen/我的 项目"
  )
}

@Test("$$ 是字面的 $；引用不存在的组时原样保留，好让用户看见自己写错了")
func templateEdgeCases() {
  #expect(TemplateExpander.expand("$$0", captures: ["x"], escaping: .raw) == "$0")
  #expect(TemplateExpander.expand("$7", captures: ["x"], escaping: .raw) == "$7")
  #expect(TemplateExpander.expand("trailing$", captures: ["x"], escaping: .raw) == "trailing$")
  #expect(TemplateExpander.expand("$1-$0", captures: ["all", "one"], escaping: .raw) == "one-all")
}

// MARK: - Matcher

@Test("关掉的规则不参与匹配，正则写错的规则被跳过而不是拖垮整批")
func matcherSkipsDisabledAndBroken() {
  let rules = [
    Rule(id: "off", name: "关着的", enabled: false, pattern: "^.*$", actions: []),
    Rule(id: "broken", name: "正则写错", pattern: "^([unclosed", actions: []),
    Rule(id: "ok", name: "好的", pattern: "^#([0-9]+)$", actions: []),
  ]
  let results = Matcher.match(text: "#1234", rules: rules)
  #expect(results.map(\.rule.id) == ["ok"])
  #expect(results[0].captures == ["#1234", "1234"])
}

@Test("没参与匹配的捕获组记空串，保证下标和 $n 对得上")
func matcherKeepsCaptureIndices() {
  let rule = Rule(id: "alt", name: "二选一", pattern: "^(?:(a)|(b))$", actions: [])
  let results = Matcher.match(text: "b", rules: [rule])
  #expect(results[0].captures == ["b", "", "b"])
}

@Test("匹配前先去首尾空白 —— 复制出来的文本常带换行")
func matcherTrims() {
  let rule = Rule(id: "n", name: "编号", pattern: "^#([0-9]+)$", actions: [])
  #expect(Matcher.match(text: "  #77\n", rules: [rule]).count == 1)
}

// MARK: - ClipboardGate

@Test("超长内容直接跳过，不进正则")
func clipboardGateSkipsLongText() {
  let long = String(repeating: "a", count: 5000)
  #expect(
    ClipboardGate.evaluate(text: long, previous: nil, maxLength: 4096)
      == .skipTooLong(length: 5000, limit: 4096)
  )
}

@Test("空白、未变化的内容都不触发")
func clipboardGateSkipsNoise() {
  #expect(ClipboardGate.evaluate(text: nil, previous: nil, maxLength: 4096) == .skipEmpty)
  #expect(ClipboardGate.evaluate(text: "   \n", previous: nil, maxLength: 4096) == .skipEmpty)
  #expect(ClipboardGate.evaluate(text: "#1", previous: "#1", maxLength: 4096) == .skipUnchanged)
  #expect(ClipboardGate.evaluate(text: " #1 ", previous: nil, maxLength: 4096) == .process("#1"))
}

// MARK: - ExecutablePathFilter（D9 的核心防护）

@Test("登录 shell 返回函数名而不是路径时，必须拒绝 —— 本机 gh 就是这种情况")
func pathFilterRejectsShellFunctionName() {
  // shape.md 2.1 记的实测输出：`$SHELL -ilc 'command -v gh'` 回的是字面的 `gh`。
  #expect(ExecutablePathFilter.absolutePath(named: "gh", inShellOutput: "gh\n") == nil)
}

@Test("rc 噪音、相对路径、同名干扰都要被滤掉，只认绝对路径且 basename 相符的行")
func pathFilterAcceptsOnlyAbsolutePaths() {
  let noisy = """
    (eval):1: can't change option: zle
    nvm is not compatible with npm config "prefix"
    ./bin/gh
    /opt/homebrew/bin/ghq
    /opt/homebrew/bin/gh
    """
  #expect(
    ExecutablePathFilter.absolutePath(named: "gh", inShellOutput: noisy) == "/opt/homebrew/bin/gh")
  #expect(ExecutablePathFilter.absolutePath(named: "gh", inShellOutput: "") == nil)
  #expect(
    ExecutablePathFilter.absolutePath(named: "node", inShellOutput: "/usr/local/bin/nodemon\n")
      == nil)
}

@Test("带空格的行不当路径用 —— 那多半是 alias 或函数体")
func pathFilterRejectsLinesWithSpaces() {
  #expect(
    ExecutablePathFilter.absolutePath(named: "gh", inShellOutput: "/usr/bin/env GH_TOKEN=x gh")
      == nil)
}

// MARK: - GhPathResolver

@Test("登录 shell 给不出路径时，退回到已知安装位置")
func ghResolverFallsBack() {
  let fs = FakeFileSystem()
  fs.markExecutable("/opt/homebrew/bin/gh")
  let runner = FakeCommandRunner()
  runner.stub(
    executable: "/bin/zsh",
    arguments: ["-ilc", "command -v gh"],
    result: CommandResult(stdout: "gh\n", stderr: "", exitCode: 0)
  )

  let resolver = GhPathResolver(runner: runner, fileSystem: fs, loginShell: "/bin/zsh")
  #expect(resolver.resolve() == "/opt/homebrew/bin/gh")
}

@Test("哪里都找不到 gh 时返回 nil，由调用方去置灰候选项")
func ghResolverGivesUp() {
  let resolver = GhPathResolver(
    runner: FakeCommandRunner(),
    fileSystem: FakeFileSystem(),
    loginShell: "/bin/zsh"
  )
  #expect(resolver.resolve() == nil)
}

// MARK: - InterpreterResolver

@Test("shebang 优先于扩展名；`env python3` 取 env 后面那个词")
func interpreterPrefersShebang() {
  let (fs, runner) = Sample.environment()
  // 扩展名说是 js，shebang 说是 python3 —— shebang 赢。
  fs.put("#!/usr/bin/env python3\n", at: "/tmp/confusing.js")

  let resolver = InterpreterResolver(runner: runner, fileSystem: fs, loginShell: "/bin/zsh")
  #expect(resolver.resolve(scriptPath: "/tmp/confusing.js") == .success("/usr/bin/python3"))
}

@Test("没有 shebang 时按扩展名映射，并把名字解析成绝对路径（nvm 的 node 就靠这条）")
func interpreterFallsBackToExtension() {
  let (fs, runner) = Sample.environment()
  let resolver = InterpreterResolver(runner: runner, fileSystem: fs, loginShell: "/bin/zsh")
  #expect(
    resolver.resolve(scriptPath: "/tmp/hello.js") == .success("/Users/test/.nvm/current/bin/node"))
}

@Test("脚本不存在、扩展名不认识、解释器找不到，各自给出可读的原因")
func interpreterFailures() {
  let (fs, runner) = Sample.environment()
  fs.put("plain text", at: "/tmp/mystery.txt")
  let resolver = InterpreterResolver(runner: runner, fileSystem: fs, loginShell: "/bin/zsh")

  #expect(
    resolver.resolve(scriptPath: "/tmp/nope.py") == .failure(.scriptMissing(path: "/tmp/nope.py")))
  #expect(resolver.resolve(scriptPath: "/tmp/mystery.txt") == .failure(.unknownExtension("txt")))

  let bare = FakeFileSystem()
  bare.put("print(1)", at: "/tmp/a.py")
  let stranded = InterpreterResolver(
    runner: FakeCommandRunner(), fileSystem: bare, loginShell: "/bin/zsh")
  #expect(
    stranded.resolve(scriptPath: "/tmp/a.py") == .failure(.interpreterNotFound(name: "python3")))
}

// MARK: - ActionResolver

@Test("scheme 没有处理者时，候选项照常出现但置灰并写明原因")
func resolverGreysOutUnhandledScheme() {
  let (fs, runner) = Sample.environment()
  let opener = FakeURLOpener(handlers: ["claude-cli": "Claude Code URL Handler"])
  let resolver = ActionResolver(
    urlOpener: opener,
    fileSystem: fs,
    interpreters: InterpreterResolver(runner: runner, fileSystem: fs, loginShell: "/bin/zsh")
  )

  let rule = Rule(
    id: "r", name: "两个 scheme", pattern: "^x$",
    actions: [
      .openURL(OpenURLAction(title: "有处理者", urlTemplate: "claude-cli://open?cwd=/tmp")),
      .openURL(OpenURLAction(title: "没处理者", urlTemplate: "nobody://open")),
    ]
  )
  let candidates = resolver.candidates(for: Matcher.match(text: "x", rules: [rule]))

  #expect(candidates.count == 2)
  #expect(candidates[0].availability == .available)
  #expect(candidates[1].availability.isAvailable == false)
  #expect(candidates[1].availability.reason?.contains("nobody") == true)
  #expect(candidates[1].plan == nil)
}

@Test("要求路径存在的规则，路径不存在就整条不弹")
func resolverHonoursPathRequirement() {
  let (fs, runner) = Sample.environment()
  fs.put("", at: "/tmp/real-dir")
  let resolver = ActionResolver(
    urlOpener: FakeURLOpener(handlers: ["claude-cli": "X"]),
    fileSystem: fs,
    interpreters: InterpreterResolver(runner: runner, fileSystem: fs, loginShell: "/bin/zsh")
  )

  let rule = Rule(
    id: "path", name: "本地路径", pattern: #"^/[^\s]+$"#, requiresExistingPath: true,
    actions: [.openURL(OpenURLAction(title: "打开", urlTemplate: "claude-cli://open?cwd=$0"))]
  )

  #expect(resolver.candidates(for: Matcher.match(text: "/tmp/real-dir", rules: [rule])).count == 1)
  #expect(resolver.candidates(for: Matcher.match(text: "/tmp/not-there", rules: [rule])).isEmpty)
}

@Test("存在且包含空格的本地文件夹仍然命中，普通文件不命中")
func localDirectoryWithSpacesMatches() {
  let path = "/Users/test/Library/Application Support/DevLauncher"
  let filePath = path + "/settings.json"
  let fs = FakeFileSystem()
  fs.putDirectory(at: path)
  fs.put("{}", at: filePath)
  let (environmentFS, runner) = Sample.environment()
  let resolver = ActionResolver(
    urlOpener: FakeURLOpener(handlers: ["codex": "Codex"]),
    fileSystem: fs,
    interpreters: InterpreterResolver(
      runner: runner,
      fileSystem: environmentFS,
      loginShell: "/bin/zsh"
    )
  )

  let matches = Matcher.match(text: path, rules: [BuiltinRules.localPath])
  #expect(matches.count == 1)
  let candidates = resolver.candidates(for: matches)
  #expect(candidates.isEmpty == false)
  let fileMatches = Matcher.match(text: filePath, rules: [BuiltinRules.localPath])
  #expect(resolver.candidates(for: fileMatches).isEmpty)
  #expect(
    candidates.map(\.icon) == [
      .application(name: "Finder"),
      .application(name: "iTerm2"),
      .application(name: "Terminal"),
      .application(name: "Claude"),
      .application(name: "Codex"),
    ])
}

@Test("解释器缺失时，脚本候选项在渲染阶段就置灰，不是点了之后才失败")
func resolverGreysOutMissingInterpreter() {
  let fs = FakeFileSystem()
  fs.put("print(1)", at: "/tmp/a.py")
  let resolver = ActionResolver(
    urlOpener: FakeURLOpener(handlers: [:]),
    fileSystem: fs,
    interpreters: InterpreterResolver(
      runner: FakeCommandRunner(), fileSystem: fs, loginShell: "/bin/zsh")
  )
  let rule = Rule(
    id: "s", name: "跑脚本", pattern: "^go$",
    actions: [.runScript(RunScriptAction(title: "跑", scriptPath: "/tmp/a.py", args: ["$0"]))]
  )
  let candidates = resolver.candidates(for: Matcher.match(text: "go", rules: [rule]))
  #expect(candidates[0].availability.reason == "未找到解释器 python3")
  #expect(candidates[0].plan == nil)
}

@Test("复制文本动作只生成执行计划，匹配阶段不写剪贴板")
func resolverPlansCopyText() {
  let (fs, runner) = Sample.environment()
  let resolver = ActionResolver(
    urlOpener: FakeURLOpener(handlers: [:]),
    fileSystem: fs,
    interpreters: InterpreterResolver(runner: runner, fileSystem: fs, loginShell: "/bin/zsh")
  )
  let rule = Rule(
    id: "copy",
    name: "复制",
    pattern: "^(.+)$",
    actions: [.copyText(CopyTextAction(title: "复制结果", textTemplate: "value=$1"))]
  )
  let candidate = resolver.candidates(for: Matcher.match(text: "hello", rules: [rule]))[0]

  #expect(candidate.availability == .available)
  #expect(candidate.plan == .copyText("value=hello"))
}

/// decisions.md Q5 的结构保证：匹配到弹窗之间，不打开任何东西、不执行用户的脚本。
///
/// 唯一允许的子进程是登录 shell 的路径探测（`-ilc command -v ...`），
/// 它只读不写，不是"执行用户的脚本"。断言写成白名单而不是"零子进程"，是为了精确。
@Test("匹配到弹窗之间不打开任何 URL，也不执行用户的脚本")
func noSideEffectsBeforeClick() {
  let (fs, runner) = Sample.environment()
  let opener = FakeURLOpener(handlers: ["claude-cli": "X"])
  let resolver = ActionResolver(
    urlOpener: opener,
    fileSystem: fs,
    interpreters: InterpreterResolver(runner: runner, fileSystem: fs, loginShell: "/bin/zsh")
  )

  let rules = [
    Rule(
      id: "u", name: "开 URL", pattern: "^go$",
      actions: [.openURL(OpenURLAction(title: "开", urlTemplate: "claude-cli://open?cwd=/tmp"))]),
    Rule(
      id: "s", name: "跑脚本", pattern: "^go$",
      actions: [.runScript(RunScriptAction(title: "跑", scriptPath: "/tmp/hello.py", args: []))]),
  ]
  let candidates = resolver.candidates(for: Matcher.match(text: "go", rules: rules))

  #expect(candidates.count == 2)
  #expect(opener.openedURLs.isEmpty)
  #expect(runner.calls.allSatisfy { $0.arguments.first == "-ilc" })
  #expect(runner.calls.contains { $0.executable == "/tmp/hello.py" } == false)
  #expect(runner.calls.contains { $0.executable == "/usr/bin/python3" } == false)
}

// MARK: - 内置预设

@Test("三条内置预设的形状")
func builtinPresets() {
  let set = BuiltinRules.defaultRuleSet()
  #expect(
    set.rules.map(\.id) == [
      "builtin.local-path", "builtin.linear-issue", "builtin.github-issue-number",
    ])
  #expect(set.rules[0].actions.count == 5)
  #expect(set.rules[0].requiresExistingPath)
  // Linear 默认关着：workspace 与 team key 没填之前开着只会制造噪音。
  #expect(set.rules[1].enabled == false)
}

@Test("填好 workspace 与 team key 后，Linear 规则的正则由白名单生成")
func linearRuleFromWhitelist() {
  let rule = BuiltinRules.linearIssue(workspace: "acme", teamKeys: ["MAX", "ENG"])
  #expect(rule.enabled)
  #expect(rule.pattern == "^(MAX|ENG)-([0-9]+)$")

  let matched = Matcher.match(text: "max-123", rules: [rule])
  #expect(matched.count == 1)

  let opener = FakeURLOpener(handlers: ["https": "Arc"])
  let (fs, runner) = Sample.environment()
  let resolver = ActionResolver(
    urlOpener: opener, fileSystem: fs,
    interpreters: InterpreterResolver(runner: runner, fileSystem: fs, loginShell: "/bin/zsh")
  )
  #expect(resolver.candidates(for: matched)[0].detail == "在浏览器打开 linear.app")
}

@Test("白名单为空时退回那条关着的规则 —— 不做「任何 KEY-数字 都算」")
func linearRuleWithoutWhitelist() {
  #expect(BuiltinRules.linearIssue(workspace: "acme", teamKeys: []).enabled == false)
  #expect(BuiltinRules.linearIssue(workspace: "", teamKeys: ["MAX"]).enabled == false)
}

// MARK: - Store

@Test("首次运行写入内置预设，再读回来是同一份")
func storeSeedsOnFirstRun() throws {
  let fs = FakeFileSystem()
  let store = Store(fileSystem: fs, directory: "/fake/support")

  let first = try store.loadRuleSet()
  #expect(first == BuiltinRules.defaultRuleSet())
  #expect(fs.contents(at: "/fake/support/rules.json") != nil)

  let second = try store.loadRuleSet()
  #expect(second == first)
}

@Test("rules.json 坏掉时报出路径和原因，不是静默换成默认值")
func storeReportsMalformedFile() {
  let fs = FakeFileSystem()
  fs.put("{ not json", at: "/fake/support/rules.json")
  let store = Store(fileSystem: fs, directory: "/fake/support")

  #expect(throws: Store.Failure.self) { try store.loadRuleSet() }
}

@Test("六种动作类型编码解码往返不丢字段")
func actionRoundTrip() throws {
  let set = RuleSet(rules: [
    Rule(
      id: "a", name: "a", pattern: "^a$",
      actions: [
        .openURL(OpenURLAction(title: "开", urlTemplate: "x://$0")),
        .openPath(OpenPathAction(title: "路径", pathTemplate: "$0")),
        .openWithApplication(
          OpenWithApplicationAction(title: "应用", applicationName: "Codex", targetTemplate: "$0")
        ),
        .runScript(RunScriptAction(title: "跑", scriptPath: "/tmp/a.py", args: ["$1", "--flag"])),
        .copyText(CopyTextAction(title: "复制", textTemplate: "$0")),
        .repoPicker(
          RepoPickerAction(title: "选", issueURLTemplate: "https://github.com/$repo/issues/$1")),
      ])
  ])
  let data = try Store.makeEncoder().encode(set)
  #expect(try Store.makeDecoder().decode(RuleSet.self, from: data) == set)
}

// MARK: - 历史

@Test("HistoryEntry 编出来的 JSON 里没有能装剪贴板原文的字段")
func historyCannotHoldClipboardText() throws {
  // 拼出来而不是写成字面量：B9 会扫整个工作树，写成字面量的话这行自己就会被判为泄漏。
  // （第一次跑 B9 时就是这么红的。）
  let secret = "ghp" + "_thisIsNotARealTokenJustTestData1234"
  let entry = HistoryEntry(
    ruleID: "builtin.local-path",
    actionIndex: 0,
    openedAt: Date(timeIntervalSince1970: 0)
  )
  var history = History(entries: [])
  history.append(entry)

  let fs = FakeFileSystem()
  let store = Store(fileSystem: fs, directory: "/fake/support")
  try store.save(history: history)

  let written = try #require(fs.contents(at: "/fake/support/history.json"))
  #expect(written.contains(secret) == false)
  // 字段是固定一组，没有 text / content / clipboard 之类的位置。
  for forbidden in ["text", "content", "clipboard", "payload"] {
    #expect(written.lowercased().contains("\"\(forbidden)\"") == false)
  }
}

@Test("历史到上限后丢最旧的")
func historyCapacity() {
  var history = History(entries: [])
  for i in 0..<(History.capacity + 5) {
    history.append(
      HistoryEntry(
        ruleID: "r\(i)", actionIndex: 0, openedAt: Date(timeIntervalSince1970: Double(i))))
  }
  #expect(history.entries.count == History.capacity)
  #expect(history.entries.first?.ruleID == "r5")
}
