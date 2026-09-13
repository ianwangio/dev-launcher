import DevLauncherCore
import Foundation
import Testing

@Test("统计按固定日历生成稳定的日、月桶并按时间倒序返回")
func activityStatisticsUsesPinnedCalendarBuckets() {
  let calendar = pinnedCalendar()
  var statistics = ActivityStatistics()

  statistics.record(
    entry(rule: "folder", action: "Finder", status: .succeeded, at: timestamp("2026-01-31T23:30:00Z")),
    calendar: calendar
  )
  statistics.record(
    entry(rule: "github", action: "Chrome", status: .failed, at: timestamp("2026-02-01T00:30:00Z")),
    calendar: calendar
  )
  statistics.record(
    entry(rule: "github", action: "Chrome", status: .succeeded, at: timestamp("2026-02-01T08:30:00Z")),
    calendar: calendar
  )

  let days = statistics.buckets(granularity: .day, year: 2026, calendar: calendar)
  #expect(days.map(\.start) == [
    timestamp("2026-02-01T00:00:00Z"), timestamp("2026-01-31T00:00:00Z"),
  ])
  #expect(days[0].totalCount == 2)
  #expect(days[0].succeededCount == 1)
  #expect(days[0].failedCount == 1)
  #expect(days[0].successRate == 0.5)

  let months = statistics.buckets(granularity: .month, year: 2026, calendar: calendar)
  #expect(months.map(\.start) == [
    timestamp("2026-02-01T00:00:00Z"), timestamp("2026-01-01T00:00:00Z"),
  ])
  #expect(months.map(\.totalCount) == [2, 1])
}

@Test("汇总提供总量、状态、成功率和稳定的规则动作排行")
func activityStatisticsSummaryIsCompleteAndDeterministic() {
  let calendar = pinnedCalendar()
  var statistics = ActivityStatistics()
  let entries = [
    entry(rule: "GitHub", action: "Chrome", status: .succeeded, at: timestamp("2026-03-01T01:00:00Z")),
    entry(rule: "Folder", action: "Finder", status: .failed, at: timestamp("2026-03-02T01:00:00Z")),
    entry(rule: "GitHub", action: "Chrome", status: .succeeded, at: timestamp("2026-03-03T01:00:00Z")),
    entry(rule: "Folder", action: "Finder", status: .succeeded, at: timestamp("2026-03-04T01:00:00Z")),
  ]
  statistics.record(contentsOf: entries, calendar: calendar)

  let summary = statistics.summary(
    from: timestamp("2026-03-01T00:00:00Z"),
    through: timestamp("2026-03-31T23:59:59Z"),
    calendar: calendar
  )
  #expect(summary.totalCount == 4)
  #expect(summary.succeededCount == 3)
  #expect(summary.failedCount == 1)
  #expect(summary.successRate == 0.75)
  #expect(summary.rankedRules.map(\.name) == ["Folder", "GitHub"])
  #expect(summary.rankedActions.map(\.name) == ["Chrome", "Finder"])
}

@Test("统计文件首次从现有活动迁移且之后不因活动裁剪或清空而丢失")
func statisticsPersistenceBootstrapsOnlyOnce() throws {
  let calendar = pinnedCalendar()
  let fileSystem = FakeFileSystem()
  let store = Store(fileSystem: fileSystem, directory: "/support")
  let initial = [
    entry(rule: "Folder", action: "Finder", status: .succeeded, at: timestamp("2026-04-01T01:00:00Z")),
    entry(rule: "GitHub", action: "Chrome", status: .failed, at: timestamp("2026-04-02T01:00:00Z")),
  ]

  var statistics = try store.loadActivityStatistics(seedEntries: initial, calendar: calendar)
  #expect(statistics.summary(calendar: calendar).totalCount == 2)
  #expect(fileSystem.fileExists(atPath: store.activityStatisticsPath))

  let ignoredSeed = initial + [
    entry(rule: "Linear", action: "Linear", status: .succeeded, at: timestamp("2026-04-03T01:00:00Z"))
  ]
  let reloaded = try store.loadActivityStatistics(seedEntries: ignoredSeed, calendar: calendar)
  #expect(reloaded.summary(calendar: calendar).totalCount == 2)

  statistics.record(ignoredSeed[2], calendar: calendar)
  try store.save(activityStatistics: statistics)
  let permanent = try store.loadActivityStatistics(seedEntries: [], calendar: calendar)
  #expect(permanent.summary(calendar: calendar).totalCount == 3)
}

@Test("统计持久化只包含安全聚合字段且年份倒序")
func statisticsEncodingIsSafeAndYearsAreReverseOrdered() throws {
  let calendar = pinnedCalendar()
  var statistics = ActivityStatistics()
  statistics.record(
    entry(rule: "Folder", action: "Finder", status: .succeeded, at: timestamp("2024-01-01T01:00:00Z")),
    calendar: calendar
  )
  statistics.record(
    entry(rule: "GitHub", action: "Chrome", status: .failed, at: timestamp("2026-01-01T01:00:00Z")),
    calendar: calendar
  )

  #expect(statistics.availableYears(calendar: calendar) == [2026, 2024])
  let encoded = String(decoding: try Store.makeEncoder().encode(statistics), as: UTF8.self).lowercased()
  for forbidden in ["clipboard", "payload", "url", "argument", "stdout", "stderr", "credential"] {
    #expect(encoded.contains(forbidden) == false)
  }
}

@Test("旧统计把 GitHub 仓库候选合并回一个动作且只迁移一次")
func legacyRepositoryCandidateStatisticsMigrateOnce() throws {
  let legacy = """
    {
      "days": [{
        "start": 0,
        "succeededCount": 3,
        "failedCount": 0,
        "ruleCounts": {"GitHub #N": 3},
        "actionCounts": {"maxgent-ai/maxgent": 2, "maxgent-ai/argocd-config": 1}
      }]
    }
    """
  var statistics = try Store.makeDecoder().decode(
    ActivityStatistics.self,
    from: Data(legacy.utf8)
  )

  let migrated = statistics.migrateLegacyRepositoryActionTitles(to: "选一个 repo 打开 issue")
  #expect(migrated)
  #expect(statistics.summary(calendar: pinnedCalendar()).rankedActions == [
    ActivityStatisticsRanking(name: "选一个 repo 打开 issue", count: 3)
  ])
  let migratedAgain = statistics.migrateLegacyRepositoryActionTitles(to: "不应再次迁移")
  #expect(migratedAgain == false)
}

private func pinnedCalendar() -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.locale = Locale(identifier: "en_US_POSIX")
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  calendar.firstWeekday = 2
  return calendar
}

private func timestamp(_ value: String) -> Date {
  ISO8601DateFormatter().date(from: value)!
}

private func entry(
  rule: String,
  action: String,
  status: ActivityStatus,
  at date: Date
) -> ActivityEntry {
  ActivityEntry(
    ruleID: rule.lowercased(),
    ruleName: rule,
    actionTitle: action,
    status: status,
    occurredAt: date
  )
}
