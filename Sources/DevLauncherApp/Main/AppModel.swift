import AppKit
import DevLauncherCore
import Foundation
import Observation

/// 把 Core 的部件和系统 adapter 接起来，并持有应用的运行时状态。
///
/// 数据流照 shape.md 3.4：
/// 剪贴板 → ClipboardGate → Matcher → ActionResolver → 面板 → 点击 → 执行 → 历史。
@MainActor
@Observable
final class AppModel {

  // MARK: 状态

  private(set) var ruleSet: RuleSet
  private(set) var settings: Settings
  private(set) var history: History
  private(set) var activity: ActivityLedger
  private(set) var activityStatistics: ActivityStatistics
  private(set) var repositorySnapshot: RepositorySnapshot?
  private(set) var repositoryError: String?
  private(set) var isRefreshingIntegrations = false
  private(set) var scriptEnvironments: [(name: String, available: Bool, detail: String)] = []
  /// 最近一次动作的结果，显示在主窗口上。脚本的 stdout/stderr 也走这里。
  private(set) var lastOutcome: String = "尚未执行过任何动作。"
  private(set) var storeDirectory: String
  private(set) var loadError: String?
  private(set) var systemBehaviorError: String?
  private(set) var listeningStatusRevision = 0
  var onListeningSettingsChanged: ((ListeningSettings) -> Void)?

  // MARK: 部件

  private let fileSystem: any FileSystem
  private let runner: any CommandRunner
  private let opener: any URLOpener
  private let applicationOpener: any ApplicationOpener
  private let clock: any Clock
  private let pasteboard: any PasteboardSource
  private let applicationContext: any ApplicationContextSource
  private let interpreters: InterpreterResolver
  private let store: Store
  private let repositoryProvider: any RepositoryProvider

  private let revealer = FinderRevealer()
  private var resolver: ActionResolver
  private var panel: PanelController?

  private var clipboardPipeline: ClipboardPipeline
  private var pollTimer: Timer?
  private var repositoryRefreshTimer: Timer?

  // MARK: 构造

  init() {
    let fileSystem = DiskFileSystem()
    let runner = ProcessCommandRunner()
    let opener = WorkspaceURLOpener()
    let applicationOpener = WorkspaceApplicationOpener()
    let clock = SystemClock()
    let pasteboard = SystemPasteboard()
    let applicationContext = WorkspaceApplicationContext()
    let loginShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    let interpreters = InterpreterResolver(
      runner: runner, fileSystem: fileSystem, loginShell: loginShell)

    let directory = Self.applicationSupportDirectory()
    let store = Store(fileSystem: fileSystem, directory: directory)
    let repositoryProvider = GitHubRepositoryProvider(
      runner: runner,
      fileSystem: fileSystem,
      clock: clock,
      loginShell: loginShell,
      cachePath: directory + "/github-repositories.json"
    )

    self.fileSystem = fileSystem
    self.runner = runner
    self.opener = opener
    self.applicationOpener = applicationOpener
    self.clock = clock
    self.pasteboard = pasteboard
    self.applicationContext = applicationContext
    self.interpreters = interpreters
    self.store = store
    self.repositoryProvider = repositoryProvider
    self.storeDirectory = directory
    self.resolver = ActionResolver(
      urlOpener: opener,
      fileSystem: fileSystem,
      interpreters: interpreters,
      applicationOpener: applicationOpener
    )
    self.clipboardPipeline = ClipboardPipeline(lastSeenChangeCount: pasteboard.changeCount)

    // 首次运行会在这里写入三条内置预设（decisions.md D5 / D8）。
    var loadError: String?
    var ruleSet = RuleSet(rules: [])
    var settings = Settings.default
    var history = History(entries: [])
    var activity = ActivityLedger()
    var activityStatistics = ActivityStatistics()
    do {
      ruleSet = try store.loadRuleSet()
      settings = try store.loadSettings()
      let configured = Self.applyingLinearConfiguration(to: ruleSet, settings: settings)
      if configured != ruleSet {
        ruleSet = configured
        try store.save(ruleSet: ruleSet)
      }
      history = try store.loadHistory()
      activity = try store.loadActivity()
      activityStatistics = try store.loadActivityStatistics(
        seedEntries: Self.normalizedStatisticsSeed(activity.entries, ruleSet: ruleSet),
        calendar: Self.localStatisticsCalendar
      )
      if let title = Self.githubActionTitle(in: ruleSet),
        activityStatistics.migrateLegacyRepositoryActionTitles(to: title)
      {
        try store.save(activityStatistics: activityStatistics)
      }
      let loadedActivityCount = activity.entries.count
      activity.trim(to: settings.activityRetentionLimit)
      if activity.entries.count != loadedActivityCount {
        try store.save(activity: activity)
      }
    } catch {
      loadError = String(describing: error)
      ruleSet = BuiltinRules.defaultRuleSet()
    }
    self.ruleSet = ruleSet
    self.settings = settings
    self.history = history
    self.activity = activity
    self.activityStatistics = activityStatistics
    self.loadError = loadError
  }

  static func applicationSupportDirectory() -> String {
    SystemPaths.applicationSupportDirectory(named: "DevLauncher")
  }

  // MARK: 生命周期

  func start() {
    panel = PanelController(onActivate: { [weak self] candidate in
      self?.activate(candidate)
    })
    warmUpInterpreters()
    if let cached = repositoryProvider.cachedRepositories() {
      applyRepositorySnapshot(cached)
      refreshScriptEnvironments()
      scheduleSelectedRepositoryRefresh(
        after: cached.selectedRefreshAttemptedAt ?? cached.fetchedAt)
    } else {
      refreshIntegrations(force: true)
    }
    startPolling()
  }

  func stop() {
    pollTimer?.invalidate()
    pollTimer = nil
    repositoryRefreshTimer?.invalidate()
    repositoryRefreshTimer = nil
    panel?.hide()
  }

  /// 解释器路径解析要起一次登录 shell，可能慢到秒级。放在启动时的后台线程做一次，
  /// 面板渲染时就只命中进程内缓存，不会卡住界面。
  private func warmUpInterpreters() {
    let interpreters = self.interpreters
    let fileSystem = self.fileSystem
    Task.detached(priority: .utility) {
      for probe in ["warm.py", "warm.js"] where fileSystem.fileExists(atPath: probe) {
        _ = interpreters.resolve(scriptPath: probe)
      }
    }
  }

  private func startPolling() {
    let interval = Double(settings.pollIntervalMilliseconds) / 1000
    pollTimer?.invalidate()
    pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
  }

  // MARK: 轮询

  /// 每 500ms 一次（decisions.md D4）。绝大多数 tick 只是一次整数比较就结束 ——
  /// 这就是"剪贴板监听要轻量"的全部实现。
  func tick() {
    let decision = clipboardPipeline.poll(
      source: pasteboard,
      context: {
        CaptureContext(
          sourceBundleIdentifier: applicationContext.frontmostBundleIdentifier,
          now: clock.now
        )
      },
      settings: settings.listening
    )

    if case .ignore(.unchangedPasteboard) = decision { return }
    if settings.panel.dismissPolicy.newClipboard { panel?.hide() }
    guard case .process(let input) = decision else { return }

    let matches = Matcher.match(input: input, rules: ruleSet.rules)
    guard !matches.isEmpty else { return }

    let candidates = resolver.candidates(for: matches)
    guard !candidates.isEmpty else { return }

    panel?.show(candidates: candidates, settings: settings.panel)
  }

  // MARK: 执行

  /// 只有走到这里才真的做事 —— decisions.md Q5：匹配只负责弹出候选。
  func activate(_ candidate: Candidate) {
    guard let plan = candidate.plan else { return }

    switch plan {
    case .open(let url):
      do {
        try opener.open(url)
        lastOutcome = "已打开 \(url)"
        record(candidate, status: .succeeded)
      } catch {
        lastOutcome = "打开失败 \(url)\n\(String(describing: error))"
        record(candidate, status: .failed)
      }

    case .script(let scriptPlan):
      lastOutcome = "正在执行 \(scriptPlan.scriptPath) …"
      let runner = self.runner
      Task.detached(priority: .userInitiated) {
        let result = Self.runScript(scriptPlan, using: runner)
        await MainActor.run {
          self.lastOutcome = result.summary
          self.record(candidate, status: result.status)
        }
      }

    case .copyText(let text):
      pasteboard.writeString(text)
      clipboardPipeline.synchronize(changeCount: pasteboard.changeCount)
      lastOutcome = "已复制 \(text.count) 个字符"
      record(candidate, status: .succeeded)

    case .openWithApplication(let target, let applicationName):
      do {
        try applicationOpener.open(target: target, withApplicationNamed: applicationName)
        lastOutcome = "已使用 \(applicationName) 打开"
        record(candidate, status: .succeeded)
      } catch {
        lastOutcome = "使用 \(applicationName) 打开失败：\(String(describing: error))"
        record(candidate, status: .failed)
      }
    }
  }

  nonisolated private static func runScript(_ plan: ScriptPlan, using runner: any CommandRunner)
    -> (summary: String, status: ActivityStatus)
  {
    do {
      let result = try runner.run(
        executable: plan.interpreter,
        arguments: [plan.scriptPath] + plan.arguments,
        environment: nil,
        timeoutSeconds: plan.timeoutSeconds
      )
      let body = [result.stdout, result.stderr]
        .filter { !$0.isEmpty }
        .joined(separator: "\n--- stderr ---\n")
      // 上限 4000 字符（decisions.md D6）。
      let clipped = body.count > 4000 ? String(body.prefix(4000)) + "\n…（已截断）" : body
      return ("退出码 \(result.exitCode)\n\(clipped)", result.exitCode == 0 ? .succeeded : .failed)
    } catch {
      return ("执行失败：\(String(describing: error))", .failed)
    }
  }

  /// 历史只记规则 id、动作序号和时间。**剪贴板原文不落盘**（decisions.md D11）——
  /// `HistoryEntry` 的字段里根本没有能装它的地方。
  private func record(_ candidate: Candidate, status: ActivityStatus) {
    let occurredAt = clock.now
    history.append(
      HistoryEntry(
        ruleID: candidate.ruleID,
        actionIndex: candidate.actionIndex,
        repo: candidate.repository,
        number: candidate.issueNumber,
        openedAt: occurredAt
      ))
    try? store.save(history: history)
    let activityEntry = ActivityEntry(
      ruleID: candidate.ruleID,
      ruleName: candidate.ruleName,
      actionTitle: activityActionTitle(for: candidate),
      status: status,
      occurredAt: occurredAt
    )
    activityStatistics.record(activityEntry, calendar: Self.localStatisticsCalendar)
    try? store.save(activityStatistics: activityStatistics)
    activity.append(
      activityEntry,
      retentionLimit: settings.activityRetentionLimit
    )
    try? store.save(activity: activity)
    rebuildResolver()
  }

  private func activityActionTitle(for candidate: Candidate) -> String {
    guard let rule = ruleSet.rules.first(where: { $0.id == candidate.ruleID }),
      rule.actions.indices.contains(candidate.actionIndex)
    else { return candidate.title }
    return rule.actions[candidate.actionIndex].title
  }

  // MARK: 规则维护

  func reloadRules() {
    do {
      ruleSet = try store.loadRuleSet()
      settings = try store.loadSettings()
      ruleSet = Self.applyingLinearConfiguration(to: ruleSet, settings: settings)
      try store.save(ruleSet: ruleSet)
      activity = try store.loadActivity()
      activityStatistics = try store.loadActivityStatistics(
        seedEntries: Self.normalizedStatisticsSeed(activity.entries, ruleSet: ruleSet),
        calendar: Self.localStatisticsCalendar
      )
      if let title = Self.githubActionTitle(in: ruleSet),
        activityStatistics.migrateLegacyRepositoryActionTitles(to: title)
      {
        try store.save(activityStatistics: activityStatistics)
      }
      activity.trim(to: settings.activityRetentionLimit)
      try store.save(activity: activity)
      loadError = nil
      startPolling()
    } catch {
      loadError = String(describing: error)
    }
  }

  @discardableResult
  func createCustomRule() -> String? {
    var catalog = RuleCatalog(ruleSet: ruleSet)
    let id = catalog.createCustom()
    return persist(catalog, returning: id)
  }

  @discardableResult
  func duplicateRule(_ id: String) -> String? {
    var catalog = RuleCatalog(ruleSet: ruleSet)
    do {
      let newID = try catalog.duplicateAsCustom(id)
      return persist(catalog, returning: newID)
    } catch {
      loadError = String(describing: error)
      return nil
    }
  }

  func setRuleEnabled(_ id: String, enabled: Bool) {
    var catalog = RuleCatalog(ruleSet: ruleSet)
    do {
      if RuleCatalog.isBuiltin(id) {
        try catalog.setBuiltinEnabled(id, enabled)
      } else {
        var draft = try catalog.draft(for: id)
        draft.enabled = enabled
        try catalog.save(draft)
      }
      _ = persist(catalog, returning: true)
    } catch {
      loadError = String(describing: error)
    }
  }

  @discardableResult
  func saveRule(_ draft: Rule) -> RuleValidation {
    var catalog = RuleCatalog(ruleSet: ruleSet)
    let validation = catalog.validate(draft)
    guard validation.isValid else { return validation }
    do {
      try catalog.save(draft)
      _ = persist(catalog, returning: true)
    } catch {
      loadError = String(describing: error)
    }
    return validation
  }

  func deleteCustomRule(_ id: String) {
    var catalog = RuleCatalog(ruleSet: ruleSet)
    do {
      try catalog.deleteCustom(id)
      _ = persist(catalog, returning: true)
    } catch {
      loadError = String(describing: error)
    }
  }

  func appendAction(_ action: Action, to ruleID: String) {
    var catalog = RuleCatalog(ruleSet: ruleSet)
    do {
      try catalog.appendAction(action, to: ruleID)
      _ = persist(catalog, returning: true)
    } catch {
      loadError = String(describing: error)
    }
  }

  func removeAction(at index: Int, from ruleID: String) {
    var catalog = RuleCatalog(ruleSet: ruleSet)
    do {
      try catalog.removeAction(at: index, from: ruleID)
      _ = persist(catalog, returning: true)
    } catch {
      loadError = String(describing: error)
    }
  }

  func restoreBuiltinActions(_ ruleID: String) {
    var catalog = RuleCatalog(ruleSet: ruleSet)
    do {
      try catalog.restoreBuiltinActions(ruleID)
      _ = persist(catalog, returning: true)
    } catch {
      loadError = String(describing: error)
    }
  }

  private func persist<T>(_ catalog: RuleCatalog, returning value: T) -> T? {
    do {
      try store.save(ruleSet: catalog.ruleSet)
      ruleSet = catalog.ruleSet
      loadError = nil
      return value
    } catch {
      loadError = String(describing: error)
      return nil
    }
  }

  func revealStoreDirectory() {
    revealer.reveal(path: store.rulesPath, inDirectory: storeDirectory)
  }

  func clipboardTextForTesting() -> String {
    pasteboard.currentString() ?? ""
  }

  func copyTestText(_ text: String) {
    guard !text.isEmpty else { return }
    pasteboard.writeString(text)
    // 这是应用自己的写入，不应该在下一次 tick 里触发浮层。
    clipboardPipeline.synchronize(changeCount: pasteboard.changeCount)
  }

  /// 手工触发一次匹配，用来在没有真实复制动作时验证整条链路。
  func previewMatch(for text: String) -> [Candidate] {
    resolver.candidates(for: Matcher.match(text: text, rules: ruleSet.rules))
  }

  func showPanel(for text: String) {
    let candidates = previewMatch(for: text)
    guard !candidates.isEmpty else {
      lastOutcome = "没有规则匹配上：\(text)"
      return
    }
    panel?.show(candidates: candidates, settings: settings.panel)
  }

  var isListening: Bool {
    _ = listeningStatusRevision
    guard let pausedUntil = settings.listening.pausedUntil else { return true }
    return pausedUntil <= clock.now
  }

  var listeningStatusTitle: String {
    isListening ? "监听中" : "已暂停"
  }

  func updateListeningSettings(_ value: ListeningSettings) {
    settings.listening = value
    persistSettings()
    startPolling()
    onListeningSettingsChanged?(value)
  }

  func updatePanelSettings(_ value: PanelSettings) {
    settings.panel = value
    persistSettings()
  }

  func pauseListening(seconds: Double) {
    settings.listening.pausedUntil = clock.now.addingTimeInterval(seconds)
    panel?.hide()
    persistSettings()
    onListeningSettingsChanged?(settings.listening)
  }

  func pauseUntilResumed() {
    settings.listening.pausedUntil = .distantFuture
    panel?.hide()
    persistSettings()
    onListeningSettingsChanged?(settings.listening)
  }

  func resumeListening() {
    settings.listening.pausedUntil = nil
    persistSettings()
    onListeningSettingsChanged?(settings.listening)
  }

  func reportSystemBehaviorError(_ message: String?) {
    systemBehaviorError = message
  }

  func refreshListeningStatus() {
    listeningStatusRevision &+= 1
  }

  func previewPanel() {
    showPanel(for: storeDirectory)
  }

  private func persistSettings() {
    do {
      try store.save(settings: settings)
      loadError = nil
    } catch {
      loadError = String(describing: error)
    }
  }

  // MARK: 集成与活动

  private static var localStatisticsCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = .autoupdatingCurrent
    calendar.timeZone = .autoupdatingCurrent
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    return calendar
  }

  var statisticsCalendar: Calendar { Self.localStatisticsCalendar }

  var statisticsNow: Date { clock.now }

  var statisticsCurrentYear: Int {
    statisticsCalendar.component(.year, from: statisticsNow)
  }

  var statisticsAvailableYears: [Int] {
    let years = activityStatistics.availableYears(calendar: statisticsCalendar)
    return Array(Set(years + [statisticsCurrentYear])).sorted(by: >)
  }

  var recentStatisticsInterval: DateInterval {
    let calendar = statisticsCalendar
    let end = statisticsNow
    let rawStart = calendar.date(byAdding: .year, value: -1, to: end) ?? end
    return DateInterval(start: calendar.startOfDay(for: rawStart), end: end)
  }

  var recentStatistics: ActivityStatisticsBucket {
    let interval = recentStatisticsInterval
    return activityStatistics.summary(
      from: interval.start,
      through: interval.end,
      calendar: statisticsCalendar
    )
  }

  var recentStatisticsDays: [ActivityStatisticsBucket] {
    let interval = recentStatisticsInterval
    return activityStatistics.days.filter {
      $0.start >= interval.start && $0.start <= interval.end
    }
  }

  func statisticsBuckets(
    granularity: ActivityStatisticsGranularity,
    year: Int
  ) -> [ActivityStatisticsBucket] {
    activityStatistics.buckets(
      granularity: granularity,
      year: year,
      calendar: statisticsCalendar
    )
  }

  nonisolated private static func normalizedStatisticsSeed(
    _ entries: [ActivityEntry],
    ruleSet: RuleSet
  ) -> [ActivityEntry] {
    let githubActionTitle = githubActionTitle(in: ruleSet)
    guard let githubActionTitle else { return entries }
    return entries.map { entry in
      guard entry.ruleID == BuiltinRules.githubIssueNumber.id else { return entry }
      var normalized = entry
      normalized.actionTitle = githubActionTitle
      return normalized
    }
  }

  nonisolated private static func githubActionTitle(in ruleSet: RuleSet) -> String? {
    ruleSet.rules
      .first(where: { $0.id == BuiltinRules.githubIssueNumber.id })?
      .actions.first?.title
  }

  func refreshIntegrations(force: Bool = true) {
    guard !isRefreshingIntegrations else { return }
    isRefreshingIntegrations = true
    repositoryError = nil
    let provider = repositoryProvider
    refreshScriptEnvironments()
    Task.detached(priority: .utility) {
      do {
        let snapshot = try await provider.repositories(
          policy: force ? .reloadIgnoringCache : .useCache)
        await MainActor.run {
          self.applyRepositorySnapshot(snapshot)
          self.repositoryError = nil
          self.isRefreshingIntegrations = false
          self.scheduleSelectedRepositoryRefresh(
            after: snapshot.selectedRefreshAttemptedAt ?? snapshot.fetchedAt)
        }
      } catch {
        await MainActor.run {
          self.repositoryError = Self.repositoryErrorMessage(error)
          self.isRefreshingIntegrations = false
          self.rebuildResolver()
          if self.repositorySnapshot != nil {
            self.scheduleSelectedRepositoryRefresh(after: self.clock.now)
          }
        }
      }
    }
  }

  private func refreshScriptEnvironments() {
    let runner = self.runner
    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    Task.detached(priority: .utility) {
      let environments = Self.detectScriptEnvironments(runner: runner, shell: shell)
      await MainActor.run { self.scriptEnvironments = environments }
    }
  }

  private func applyRepositorySnapshot(_ snapshot: RepositorySnapshot) {
    repositorySnapshot = snapshot
    initializeRepositorySelectionIfNeeded(from: snapshot)
    rebuildResolver()
  }

  private func scheduleSelectedRepositoryRefresh(after lastAttemptAt: Date?) {
    repositoryRefreshTimer?.invalidate()
    repositoryRefreshTimer = nil

    let delay = RepositoryRefreshSchedule.delay(lastAttemptAt: lastAttemptAt, now: clock.now)
    guard delay > 0 else {
      refreshSelectedRepositories()
      return
    }
    repositoryRefreshTimer = Timer.scheduledTimer(
      withTimeInterval: delay, repeats: false
    ) { [weak self] _ in
      Task { @MainActor in self?.refreshSelectedRepositories() }
    }
  }

  private func refreshSelectedRepositories() {
    guard !isRefreshingIntegrations else { return }
    isRefreshingIntegrations = true
    repositoryError = nil
    let provider = repositoryProvider
    let selected = Set(settings.githubSelectedRepositories ?? [])
    Task.detached(priority: .utility) {
      do {
        let result = try await provider.refreshSelectedRepositories(selected)
        await MainActor.run {
          self.applyRepositorySnapshot(result.snapshot)
          self.repositoryError = result.failedRepositories.isEmpty
            ? nil
            : "部分已勾选仓库刷新失败，已保留缓存：\(result.failedRepositories.joined(separator: ", "))"
          self.isRefreshingIntegrations = false
          self.scheduleSelectedRepositoryRefresh(
            after: result.snapshot.selectedRefreshAttemptedAt ?? self.clock.now)
        }
      } catch {
        await MainActor.run {
          self.repositoryError = Self.repositoryErrorMessage(error)
          self.isRefreshingIntegrations = false
          self.scheduleSelectedRepositoryRefresh(after: self.clock.now)
        }
      }
    }
  }

  func updateLinear(workspace: String, teamKeys: [String]) {
    let cleanWorkspace = workspace.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanKeys = teamKeys.map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }.filter { !$0.isEmpty }
    settings.linearWorkspace = cleanWorkspace
    settings.linearTeamKeys = Array(Set(cleanKeys)).sorted()
    persistSettings()

    let replacement = BuiltinRules.linearIssue(
      workspace: settings.linearWorkspace,
      teamKeys: settings.linearTeamKeys
    )
    if let index = ruleSet.rules.firstIndex(where: { $0.id == replacement.id }) {
      ruleSet.rules[index] = replacement
      try? store.save(ruleSet: ruleSet)
    }
  }

  func clearActivity() {
    activity.clear()
    do {
      try store.save(activity: activity)
      loadError = nil
    } catch {
      loadError = String(describing: error)
    }
  }

  func updateActivityRetentionLimit(_ limit: Int) {
    guard ActivityLedger.supportedRetentionLimits.contains(limit) else { return }
    settings.activityRetentionLimit = limit
    activity.trim(to: limit)
    do {
      try store.save(settings: settings)
      try store.save(activity: activity)
      loadError = nil
    } catch {
      loadError = String(describing: error)
    }
  }

  func isRepositorySelected(_ name: String) -> Bool {
    settings.githubSelectedRepositories?.contains(name) ?? false
  }

  func setRepositorySelected(_ name: String, selected: Bool) {
    var selectedNames = Set(
      settings.githubSelectedRepositories
        ?? (repositorySnapshot?.repositories.map(\.nameWithOwner) ?? [])
    )
    if selected { selectedNames.insert(name) } else { selectedNames.remove(name) }
    settings.githubSelectedRepositories = selectedNames.sorted()
    persistSettings()
    rebuildResolver()
  }

  func selectAllRepositories() {
    settings.githubSelectedRepositories = repositorySnapshot?.repositories.map(\.nameWithOwner).sorted() ?? []
    persistSettings()
    rebuildResolver()
  }

  func deselectAllRepositories() {
    settings.githubSelectedRepositories = []
    persistSettings()
    rebuildResolver()
  }

  func replaceRepositorySelection(in scope: [String], with selected: [String]) {
    var names = Set(settings.githubSelectedRepositories ?? [])
    names.subtract(scope)
    names.formUnion(selected)
    settings.githubSelectedRepositories = names.sorted()
    persistSettings()
    rebuildResolver()
  }

  private func initializeRepositorySelectionIfNeeded(from snapshot: RepositorySnapshot) {
    guard settings.githubSelectedRepositories == nil else { return }
    settings.githubSelectedRepositories = RepoRanker.mostRecentlyUpdated(
      snapshot.repositories, limit: 10
    ).map(\.nameWithOwner)
    persistSettings()
  }

  var installedApplications: [(name: String, installed: Bool)] {
    ["Finder", "iTerm2", "Terminal", "Zed", "Google Chrome", "Claude", "Codex"].map {
      ($0, applicationOpener.isApplicationAvailable(named: $0))
    }
  }

  func selectIgnoredApplications() -> [InstalledApplicationDescriptor] {
    ApplicationSelectionAdapter().selectApplications()
  }

  func ignoredApplicationDescriptor(for bundleIdentifier: String)
    -> InstalledApplicationDescriptor
  {
    ApplicationIconProvider.descriptor(bundleIdentifier: bundleIdentifier)
  }

  nonisolated private static func detectScriptEnvironments(
    runner: any CommandRunner,
    shell: String
  ) -> [(name: String, available: Bool, detail: String)] {
    [("Python", "python3"), ("Node.js", "node")].map { title, executable in
      guard let result = try? runner.run(
        executable: shell,
        arguments: ["-ilc", "command -v \(executable)"],
        environment: nil,
        timeoutSeconds: 5
      ), result.exitCode == 0,
        let path = result.stdout.split(separator: "\n").map(String.init).first(where: { $0.hasPrefix("/") })
      else { return (title, false, "未找到 \(executable)") }
      return (title, true, path)
    }
  }

  private func rebuildResolver() {
    let repositories = repositorySnapshot?.repositories ?? []
    let selectedRepositories: [GitHubRepository]
    if let selection = settings.githubSelectedRepositories {
      let names = Set(selection)
      selectedRepositories = repositories.filter { names.contains($0.nameWithOwner) }
    } else {
      selectedRepositories = repositories
    }
    resolver = ActionResolver(
      urlOpener: opener,
      fileSystem: fileSystem,
      interpreters: interpreters,
      applicationOpener: applicationOpener,
      repositories: selectedRepositories,
      history: history.entries
    )
  }

  nonisolated private static func repositoryErrorMessage(_ error: any Error) -> String {
    switch error {
    case RepositoryProviderFailure.ghUnavailable: return "未找到 GitHub CLI（gh）"
    case RepositoryProviderFailure.authenticationUnavailable: return "GitHub CLI 尚未登录"
    case RepositoryProviderFailure.commandFailed(let detail): return detail
    case RepositoryProviderFailure.malformedResponse(let detail): return detail
    default: return String(describing: error)
    }
  }

  nonisolated private static func applyingLinearConfiguration(
    to ruleSet: RuleSet,
    settings: Settings
  ) -> RuleSet {
    guard !settings.linearWorkspace.isEmpty, !settings.linearTeamKeys.isEmpty else { return ruleSet }
    var result = ruleSet
    guard let index = result.rules.firstIndex(where: { $0.id == BuiltinRules.linearIssue.id })
    else { return result }
    let wasEnabled = result.rules[index].enabled
    var configured = BuiltinRules.linearIssue(
      workspace: settings.linearWorkspace,
      teamKeys: settings.linearTeamKeys
    )
    configured.enabled = wasEnabled
    result.rules[index] = configured
    return result
  }
}
