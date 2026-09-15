import DevLauncherCore
import Foundation
import Testing

@Test("GitHub provider 合并多账号、过滤归档仓库、去重并写入 24 小时缓存")
func repositoryProviderMultiAccountAndCache() async throws {
  let fs = FakeFileSystem()
  fs.markExecutable("/opt/homebrew/bin/gh")
  let runner = FakeCommandRunner()
  runner.stub(
    executable: "/bin/zsh", arguments: ["-ilc", "command -v gh"],
    result: CommandResult(stdout: "/opt/homebrew/bin/gh\n", stderr: "", exitCode: 0))
  runner.stub(
    executable: "/opt/homebrew/bin/gh", arguments: ["auth", "status", "--json", "hosts"],
    result: CommandResult(
      stdout: #"{"hosts":{"github.com":[{"state":"success","host":"github.com","login":"alice"},{"state":"success","host":"github.com","login":"bob"}]}}"#,
      stderr: "", exitCode: 0))
  for account in ["alice", "bob"] {
    runner.stub(
      executable: "/opt/homebrew/bin/gh",
      arguments: ["auth", "token", "--hostname", "github.com", "--user", account],
      result: CommandResult(stdout: "token-\(account)\n", stderr: "", exitCode: 0))
  }
  let accountArguments = [
    "api", "graphql", "--hostname", "github.com",
    "-f", "query=\(GitHubRepositoryProvider.accountQuery)",
  ]
  runner.stub(
    executable: "/opt/homebrew/bin/gh", arguments: accountArguments,
    result: CommandResult(
      stdout: #"{"data":{"viewer":{"login":"alice","organizations":{"nodes":[{"login":"acme","name":"Acme"}]}}}}"#,
      stderr: "", exitCode: 0))
  let repositoryArguments: (String) -> [String] = { owner in
    [
      "api", "graphql", "--hostname", "github.com", "--paginate", "--slurp",
      "-F", "owner=\(owner)", "-f", "query=\(GitHubRepositoryProvider.repositoryQuery)",
    ]
  }
  runner.stub(
    executable: "/opt/homebrew/bin/gh", arguments: repositoryArguments("alice"),
    result: CommandResult(
      stdout: #"[{"data":{"repositoryOwner":{"repositories":{"nodes":[{"nameWithOwner":"alice/personal","pushedAt":"2026-09-10T00:00:00Z","pullRequests":{"nodes":[]}}]}}}}]"#,
      stderr: "", exitCode: 0))
  runner.stub(
    executable: "/opt/homebrew/bin/gh", arguments: repositoryArguments("acme"),
    result: CommandResult(
      stdout: #"[{"data":{"repositoryOwner":{"repositories":{"nodes":[{"nameWithOwner":"acme/shared","pushedAt":"2026-09-12T00:00:00Z","pullRequests":{"nodes":[{"number":82}]}},{"nameWithOwner":"acme/active","pushedAt":"2026-09-11T00:00:00Z","pullRequests":{"nodes":[]}}]}}}}]"#,
      stderr: "", exitCode: 0))

  let provider = GitHubRepositoryProvider(
    runner: runner, fileSystem: fs,
    clock: FakeClock(now: Date(timeIntervalSince1970: 2_000_000_000)),
    loginShell: "/bin/zsh", cachePath: "/cache/repos.json")
  let first = try await provider.repositories(policy: .reloadIgnoringCache)
  #expect(first.accounts == ["alice@github.com", "bob@github.com"])
  #expect(Set(first.repositories.map(\.nameWithOwner)) == ["alice/personal", "acme/shared", "acme/active"])
  #expect(first.repositories.first { $0.nameWithOwner == "acme/shared" }?.latestPullRequestNumber == 82)
  #expect(first.repositories.first { $0.nameWithOwner == "acme/shared" }?.accountIDs.count == 2)
  #expect(first.organizations.map(\.login) == ["acme", "acme"])
  #expect(fs.contents(at: "/cache/repos.json") != nil)

  let callCount = runner.calls.count
  let second = try await provider.repositories(policy: .useCache)
  #expect(second == first)
  #expect(runner.calls.count == callCount)
}

@Test("过期缓存会在 GitHub 刷新失败时作为可用降级返回")
func repositoryProviderUsesStaleCacheOnFailure() async throws {
  let fs = FakeFileSystem()
  let old = RepositorySnapshot(
    repositories: [GitHubRepository(nameWithOwner: "org/cached")],
    accounts: ["alice@github.com"],
    fetchedAt: Date(timeIntervalSince1970: 0))
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  fs.put(String(decoding: try encoder.encode(old), as: UTF8.self), at: "/cache/repos.json")
  let provider = GitHubRepositoryProvider(
    runner: FakeCommandRunner(), fileSystem: fs,
    clock: FakeClock(now: Date(timeIntervalSince1970: 2_000_000_000)),
    loginShell: "/bin/zsh", cachePath: "/cache/repos.json")
  #expect(try await provider.repositories(policy: .useCache) == old)
}

@Test("仓库排序按最近选择、推送时间、名称三层稳定排列")
func repositoryRanking() {
  let recent = Date(timeIntervalSince1970: 300)
  let repositories = [
    GitHubRepository(nameWithOwner: "org/z", pushedAt: Date(timeIntervalSince1970: 200)),
    GitHubRepository(nameWithOwner: "org/a", pushedAt: Date(timeIntervalSince1970: 200)),
    GitHubRepository(nameWithOwner: "org/used", pushedAt: Date(timeIntervalSince1970: 10)),
  ]
  let ranked = RepoRanker.rank(
    repositories,
    history: [HistoryEntry(ruleID: "r", actionIndex: 0, repo: "org/used", openedAt: recent)])
  #expect(ranked.map(\.nameWithOwner) == ["org/used", "org/a", "org/z"])
}

@Test("复制编号时按最新 PR 编号的绝对距离排列仓库")
func repositoryRecommendationUsesAbsolutePRNumberDistance() {
  let repositories = [
    GitHubRepository(nameWithOwner: "org/too-small", latestPullRequestNumber: 39),
    GitHubRepository(nameWithOwner: "org/far", latestPullRequestNumber: 300),
    GitHubRepository(nameWithOwner: "org/closest", latestPullRequestNumber: 45),
    GitHubRepository(nameWithOwner: "org/unknown"),
  ]
  let ranked = RepoRanker.rank(repositories, history: [], referenceNumber: 42)
  #expect(ranked.map(\.nameWithOwner) == ["org/closest", "org/too-small", "org/far", "org/unknown"])
  #expect(RepoRanker.isRecommended(ranked[0], for: 42))
  #expect(RepoRanker.isRecommended(ranked[1], for: 42))
  #expect(RepoRanker.isRecommended(ranked[2], for: 42) == false)
}

@Test("#272 在缓存落后一位时仍推荐 ArgoCD Config")
func repositoryRecommendationHandlesStalePRMetadata() {
  let repositories = [
    GitHubRepository(nameWithOwner: "maxgent-ai/maxgent", latestPullRequestNumber: 5293),
    GitHubRepository(nameWithOwner: "maxgent-ai/maxgent-terraform", latestPullRequestNumber: 268),
    GitHubRepository(nameWithOwner: "maxgent-ai/argocd-config", latestPullRequestNumber: 271),
  ]

  let ranked = RepoRanker.rank(repositories, history: [], referenceNumber: 272)

  #expect(ranked.map(\.nameWithOwner) == [
    "maxgent-ai/argocd-config",
    "maxgent-ai/maxgent-terraform",
    "maxgent-ai/maxgent",
  ])
  #expect(RepoRanker.isRecommended(ranked[0], for: 272))
}

@Test("仓库推荐距离以三为边界")
func repositoryRecommendationUsesConfidenceThreshold() {
  #expect(RepoRanker.isRecommended(
    GitHubRepository(nameWithOwner: "org/within", latestPullRequestNumber: 269),
    for: 272))
  #expect(RepoRanker.isRecommended(
    GitHubRepository(nameWithOwner: "org/outside", latestPullRequestNumber: 268),
    for: 272) == false)
  #expect(RepoRanker.isRecommended(
    GitHubRepository(nameWithOwner: "org/unknown"),
    for: 272) == false)
}

@Test("绝对距离相同时优先最近使用的仓库")
func repositoryRecommendationBreaksDistanceTieWithHistory() {
  let repositories = [
    GitHubRepository(nameWithOwner: "org/above", latestPullRequestNumber: 45),
    GitHubRepository(nameWithOwner: "org/below", latestPullRequestNumber: 39),
  ]
  let ranked = RepoRanker.rank(
    repositories,
    history: [HistoryEntry(
      ruleID: "r", actionIndex: 0, repo: "org/below", number: 39,
      openedAt: Date(timeIntervalSince1970: 300))],
    referenceNumber: 42)

  #expect(ranked.map(\.nameWithOwner) == ["org/below", "org/above"])
}

@Test("GitHub repoPicker 展开成真实仓库候选并保留排序元数据")
func repositoryPickerCandidates() throws {
  let fs = FakeFileSystem()
  let resolver = ActionResolver(
    urlOpener: FakeURLOpener(handlers: ["https": "Browser"]),
    fileSystem: fs,
    interpreters: InterpreterResolver(runner: FakeCommandRunner(), fileSystem: fs, loginShell: "/bin/zsh"),
    repositories: [GitHubRepository(nameWithOwner: "openai/codex", latestPullRequestNumber: 43)]
  )
  let candidates = resolver.candidates(
    for: Matcher.match(text: "#42", rules: [BuiltinRules.githubIssueNumber]))
  let candidate = try #require(candidates.first)
  #expect(candidate.repository == "openai/codex")
  #expect(candidate.issueNumber == 42)
  #expect(candidate.icon == .application(name: "GitHub Desktop"))
  #expect(candidate.detail.contains("推荐"))
  #expect(candidate.plan == .open(url: "https://github.com/openai/codex/issues/42"))
}

@Test("GitHub repoPicker 不为距离过大的首位候选显示推荐")
func repositoryPickerOmitsLowConfidenceRecommendation() throws {
  let fs = FakeFileSystem()
  let resolver = ActionResolver(
    urlOpener: FakeURLOpener(handlers: ["https": "Browser"]),
    fileSystem: fs,
    interpreters: InterpreterResolver(
      runner: FakeCommandRunner(), fileSystem: fs, loginShell: "/bin/zsh"),
    repositories: [GitHubRepository(
      nameWithOwner: "maxgent-ai/maxgent", latestPullRequestNumber: 5293)]
  )

  let candidates = resolver.candidates(
    for: Matcher.match(text: "#272", rules: [BuiltinRules.githubIssueNumber]))
  let candidate = try #require(candidates.first)

  #expect(candidate.repository == "maxgent-ai/maxgent")
  #expect(candidate.detail.contains("推荐") == false)
  #expect(candidate.detail.contains("最新 PR #5293"))
}

@Test("Linear 配置生成正确匹配和网页链接")
func linearConfigurationCandidate() throws {
  let rule = BuiltinRules.linearIssue(workspace: "acme", teamKeys: ["ENG", "APP"])
  let fs = FakeFileSystem()
  let resolver = ActionResolver(
    urlOpener: FakeURLOpener(handlers: ["https": "Browser"]),
    fileSystem: fs,
    interpreters: InterpreterResolver(runner: FakeCommandRunner(), fileSystem: fs, loginShell: "/bin/zsh"))
  let candidate = try #require(resolver.candidates(for: Matcher.match(text: "ENG-17", rules: [rule])).first)
  #expect(candidate.plan == .open(url: "https://linear.app/acme/issue/ENG-17"))
}

@Test("活动账本只有白名单元数据、支持容量限制和清空")
func activityLedgerPrivacyAndClear() throws {
  var ledger = ActivityLedger()
  ledger.append(ActivityEntry(
    ruleID: "r", ruleName: "规则", actionTitle: "打开", status: .succeeded,
    occurredAt: Date(timeIntervalSince1970: 0)))
  let encoded = String(decoding: try Store.makeEncoder().encode(ledger), as: UTF8.self)
  for forbidden in ["clipboard", "content", "payload", "url", "argument", "stdout", "stderr", "credential"] {
    #expect(encoded.lowercased().contains("\"\(forbidden)\"") == false)
  }
  ledger.clear()
  #expect(ledger.entries.isEmpty)
}

@Test("GitHub 仓库勾选配置区分首次初始化与明确全不选")
func repositorySelectionSettingsRoundTrip() throws {
  var settings = Settings.default
  #expect(settings.githubSelectedRepositories == nil)
  settings.githubSelectedRepositories = []
  let emptyData = try Store.makeEncoder().encode(settings)
  #expect(try Store.makeDecoder().decode(Settings.self, from: emptyData).githubSelectedRepositories == [])
  settings.githubSelectedRepositories = ["openai/codex", "org/tool"]
  let selectedData = try Store.makeEncoder().encode(settings)
  #expect(
    try Store.makeDecoder().decode(Settings.self, from: selectedData).githubSelectedRepositories
      == ["openai/codex", "org/tool"])
}

@Test("首次初始化只选择最后更新的十个仓库")
func initialRepositorySelectionUsesLatestTen() {
  let repositories = (0..<14).map { index in
    GitHubRepository(
      nameWithOwner: "org/repo-\(index)",
      pushedAt: Date(timeIntervalSince1970: Double(index))
    )
  }
  let selected = RepoRanker.mostRecentlyUpdated(repositories, limit: 10)
  #expect(selected.map(\.nameWithOwner) == (4..<14).reversed().map { "org/repo-\($0)" })
}
