import Foundation

/// 首次运行写入的三条内置预设（decisions.md D8）。
///
/// 这些是**用 Core 的类型构造出来的值**，不是手写的 JSON 字面量 ——
/// 手写 JSON 就等于第二份真相（shape.md 第 0 节），由 B5 守。
public enum BuiltinRules {

  public static func defaultRuleSet() -> RuleSet {
    RuleSet(rules: [localPath, linearIssue, githubIssueNumber])
  }

  /// 1 · 本地文件夹：以 `/` 或 `~/` 开头，允许目录名包含空格，且磁盘上确实是文件夹。
  public static let localPath = Rule(
    id: "builtin.local-path",
    name: "本地文件夹",
    condition: .group(
      ConditionGroup(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000100")!,
        combinator: .all,
        children: [
          .predicate(
            ConditionPredicate(
              id: UUID(uuidString: "00000000-0000-4000-8000-000000000101")!,
              field: .text,
              operation: .matchesRegularExpression,
              value: #"^(?:/|~/).+$"#
            )
          ),
          .predicate(
            ConditionPredicate(
              id: UUID(uuidString: "00000000-0000-4000-8000-000000000102")!,
              field: .fileExists,
              operation: .isTrue,
              value: "true"
            )
          ),
          .predicate(
            ConditionPredicate(
              id: UUID(uuidString: "00000000-0000-4000-8000-000000000103")!,
              field: .fileKind,
              operation: .equals,
              value: "directory"
            )
          ),
        ]
      )
    ),
    actions: [
      .openWithApplication(
        OpenWithApplicationAction(
          title: "在 Finder 中显示",
          applicationName: "Finder",
          targetTemplate: "{{匹配内容}}"
        )
      ),
      .openWithApplication(
        OpenWithApplicationAction(
          title: "在 iTerm2 中打开",
          applicationName: "iTerm2",
          targetTemplate: "{{匹配内容}}"
        )
      ),
      .openURL(OpenURLAction(title: "Claude Code 终端", urlTemplate: "claude-cli://open?cwd=$0")),
      .openURL(OpenURLAction(title: "Claude Code 桌面", urlTemplate: "claude://code/new?folder=$0")),
      .openURL(OpenURLAction(title: "Codex 桌面", urlTemplate: "codex://threads/new?path=$0")),
    ]
  )

  /// 2 · Linear issue。默认关着：正则里的 team key 和 URL 里的 workspace 都要先填。
  /// 填好之后用 `linearIssue(workspace:teamKeys:)` 重新生成这条规则。
  public static let linearIssue = Rule(
    id: "builtin.linear-issue",
    name: "Linear issue（填好 workspace 与 team key 后启用）",
    enabled: false,
    condition: builtinRegex(
      id: "00000000-0000-4000-8000-000000000201",
      pattern: #"^(EXAMPLE)-([0-9]+)$"#,
      caseInsensitive: true
    ),
    actions: [
      .openURL(
        OpenURLAction(
          title: "在 Linear 打开",
          urlTemplate: "https://linear.app/EXAMPLE-WORKSPACE/issue/$0"
        ))
    ]
  )

  /// 按设置里的 workspace 与 team key 白名单重新生成 Linear 规则。
  /// 白名单为空时返回一条关着的规则 —— 没有白名单就匹配任意 `KEY-数字` 会把面板变成噪音源。
  public static func linearIssue(workspace: String, teamKeys: [String]) -> Rule {
    let keys = teamKeys.filter { !$0.isEmpty }
    guard !keys.isEmpty, !workspace.isEmpty else { return linearIssue }

    let alternation = keys.map { NSRegularExpression.escapedPattern(for: $0) }.joined(
      separator: "|")
    return Rule(
      id: "builtin.linear-issue",
      name: "Linear issue",
      enabled: true,
      condition: builtinRegex(
        id: "00000000-0000-4000-8000-000000000201",
        pattern: "^(\(alternation))-([0-9]+)$",
        caseInsensitive: true
      ),
      actions: [
        .openURL(
          OpenURLAction(
            title: "在 Linear 打开",
            urlTemplate: "https://linear.app/\(workspace)/issue/$0"
          ))
      ]
    )
  }

  /// 3 · GitHub `#N`：列出 repo 供选择，再打开对应 issue。
  public static let githubIssueNumber = Rule(
    id: "builtin.github-issue-number",
    name: "GitHub #N",
    condition: builtinRegex(
      id: "00000000-0000-4000-8000-000000000301",
      pattern: #"^#([0-9]+)$"#
    ),
    actions: [
      .repoPicker(
        RepoPickerAction(
          title: "选一个 repo 打开 issue",
          issueURLTemplate: "https://github.com/$repo/issues/$1"
        ))
    ]
  )

  private static func builtinRegex(
    id: String,
    pattern: String,
    caseInsensitive: Bool = false
  ) -> ConditionExpression {
    .predicate(
      ConditionPredicate(
        id: UUID(uuidString: id)!,
        field: .text,
        operation: .matchesRegularExpression,
        value: pattern,
        caseInsensitive: caseInsensitive
      )
    )
  }
}
