import DevLauncherCore
import Foundation
import Testing

@Test("活动保留设置提供五档并随 Settings 编码往返")
func activityRetentionSettingsRoundTrip() throws {
  #expect(ActivityLedger.supportedRetentionLimits == [100, 500, 1000, 2000, 5000])

  var settings = Settings.default
  #expect(settings.activityRetentionLimit == 1000)
  settings.activityRetentionLimit = 5000

  let data = try Store.makeEncoder().encode(settings)
  #expect(try Store.makeDecoder().decode(Settings.self, from: data) == settings)
}

@Test("旧设置没有活动上限时迁移为 1000")
func legacySettingsUseDefaultActivityRetention() throws {
  let legacy = """
    {
      "version": 6,
      "listening": {},
      "panel": {},
      "linearWorkspace": "",
      "linearTeamKeys": []
    }
    """

  let settings = try Store.makeDecoder().decode(Settings.self, from: Data(legacy.utf8))
  #expect(settings.activityRetentionLimit == 1000)
}

@Test("活动账本调低上限后只保留最新记录且后续追加继续裁剪")
func activityLedgerUsesDynamicRetentionLimit() {
  let entries = (0..<8).map(activityEntry)
  var ledger = ActivityLedger(entries: entries, retentionLimit: 5)
  #expect(ledger.entries.map(\.ruleID) == ["r3", "r4", "r5", "r6", "r7"])

  ledger.trim(to: 3)
  #expect(ledger.entries.map(\.ruleID) == ["r5", "r6", "r7"])

  ledger.append(activityEntry(8), retentionLimit: 3)
  #expect(ledger.entries.map(\.ruleID) == ["r6", "r7", "r8"])
}

@Test("活动文件继续只编码记录而不编码保留设置")
func activityFileDoesNotEncodeRetentionSetting() throws {
  let ledger = ActivityLedger(entries: [activityEntry(1)], retentionLimit: 5000)
  let encoded = String(decoding: try Store.makeEncoder().encode(ledger), as: UTF8.self)

  #expect(encoded.contains("entries"))
  #expect(encoded.contains("retention") == false)
  #expect(encoded.contains("capacity") == false)
}

@Test("活动页包含已验收的上限控件和裁剪说明")
func activityViewContainsAcceptedRetentionControls() throws {
  let path = SourceTree.root + "/Sources/DevLauncherApp/Main/ActivityView.swift"
  let source = try String(contentsOfFile: path, encoding: .utf8)

  #expect(source.contains("最多保留"))
  #expect(source.contains("ActivityLedger.supportedRetentionLimits"))
  #expect(source.contains("调低上限会立即删除较早的记录"))
  #expect(source.contains("model.updateActivityRetentionLimit"))
}

private func activityEntry(_ index: Int) -> ActivityEntry {
  ActivityEntry(
    ruleID: "r\(index)",
    ruleName: "规则 \(index)",
    actionTitle: "动作 \(index)",
    status: .succeeded,
    occurredAt: Date(timeIntervalSince1970: Double(index))
  )
}
