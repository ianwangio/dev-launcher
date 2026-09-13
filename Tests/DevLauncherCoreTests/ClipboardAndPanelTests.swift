import DevLauncherCore
import Foundation
import Testing

private final class CountingPasteboardSource: PasteboardSource, @unchecked Sendable {
  var changeCount: Int
  var snapshotCalls = 0
  var currentStringCalls = 0
  var writtenStrings: [String] = []
  var value: PasteboardSnapshot

  init(changeCount: Int, value: PasteboardSnapshot) {
    self.changeCount = changeCount
    self.value = value
  }

  func snapshot() -> PasteboardSnapshot {
    snapshotCalls += 1
    return value
  }

  func currentString() -> String? {
    currentStringCalls += 1
    return value.plainText
  }

  func writeString(_ value: String) {
    writtenStrings.append(value)
  }
}

@Test("空闲轮询只读 changeCount，不获取快照或前台应用")
func idleClipboardPollIsConstantTime() {
  let source = CountingPasteboardSource(
    changeCount: 10,
    value: PasteboardSnapshot(plainText: "unchanged")
  )
  var contextCalls = 0
  var pipeline = ClipboardPipeline(lastSeenChangeCount: 10)

  let idle = pipeline.poll(
    source: source,
    context: {
      contextCalls += 1
      return CaptureContext(
        sourceBundleIdentifier: "com.example.app",
        now: Date(timeIntervalSince1970: 0)
      )
    },
    settings: .default
  )
  #expect(idle == .ignore(.unchangedPasteboard))
  #expect(source.snapshotCalls == 0)
  #expect(contextCalls == 0)

  source.changeCount = 11
  _ = pipeline.poll(
    source: source,
    context: {
      contextCalls += 1
      return CaptureContext(
        sourceBundleIdentifier: "com.example.app",
        now: Date(timeIntervalSince1970: 0)
      )
    },
    settings: .default
  )
  #expect(source.snapshotCalls == 1)
  #expect(contextCalls == 1)
}

@Test("每个新 changeCount 都处理，即使文本与上次相同")
func clipboardPipelineAllowsRepeatedCopies() {
  var pipeline = ClipboardPipeline(lastSeenChangeCount: 10)
  let context = CaptureContext(
    sourceBundleIdentifier: "com.apple.Safari", now: Date(timeIntervalSince1970: 0))
  let snapshot = PasteboardSnapshot(plainText: "#42")

  #expect(
    pipeline.consume(changeCount: 11, snapshot: snapshot, context: context, settings: .default)
      == .process(
        NormalizedClipboard(
          text: "#42",
          kind: .plainText,
          sourceBundleIdentifier: "com.apple.Safari"
        )
      )
  )
  #expect(
    pipeline.consume(changeCount: 12, snapshot: snapshot, context: context, settings: .default)
      == .process(
        NormalizedClipboard(
          text: "#42",
          kind: .plainText,
          sourceBundleIdentifier: "com.apple.Safari"
        )
      )
  )
}

@Test("关闭重复触发时，相同文本被明确忽略")
func clipboardPipelineCanSuppressRepeatedText() {
  var settings = ListeningSettings.default
  settings.repeatIdenticalCopies = false
  var pipeline = ClipboardPipeline(lastSeenChangeCount: 1)
  let context = CaptureContext(sourceBundleIdentifier: nil, now: Date(timeIntervalSince1970: 0))
  let snapshot = PasteboardSnapshot(plainText: "same")

  #expect(
    pipeline.consume(changeCount: 2, snapshot: snapshot, context: context, settings: settings)
      == .process(NormalizedClipboard(text: "same"))
  )
  #expect(
    pipeline.consume(changeCount: 3, snapshot: snapshot, context: context, settings: settings)
      == .ignore(.repeatedText)
  )
}

@Test("文件、URL、纯文本与富文本按稳定优先级归一化")
func clipboardRepresentationsHaveStablePriority() {
  let context = CaptureContext(sourceBundleIdentifier: nil, now: Date(timeIntervalSince1970: 0))
  let snapshot = PasteboardSnapshot(
    plainText: "https://example.com/plain",
    urlString: "https://example.com/url",
    filePaths: ["/tmp/project"],
    richText: "rich"
  )
  var all = ClipboardPipeline(lastSeenChangeCount: 0)
  #expect(
    all.consume(changeCount: 1, snapshot: snapshot, context: context, settings: .default)
      == .process(NormalizedClipboard(text: "/tmp/project", kind: .file))
  )

  var settings = ListeningSettings.default
  settings.acceptedContentKinds.remove(.file)
  var noFile = ClipboardPipeline(lastSeenChangeCount: 0)
  #expect(
    noFile.consume(changeCount: 1, snapshot: snapshot, context: context, settings: settings)
      == .process(NormalizedClipboard(text: "https://example.com/url", kind: .url))
  )
}

@Test("暂停和忽略应用在进入规则引擎前阻断")
func clipboardPipelineHonorsPauseAndIgnoredApps() {
  let now = Date(timeIntervalSince1970: 100)
  let snapshot = PasteboardSnapshot(plainText: "text")
  var settings = ListeningSettings.default
  settings.pausedUntil = Date(timeIntervalSince1970: 200)
  var paused = ClipboardPipeline(lastSeenChangeCount: 0)
  #expect(
    paused.consume(
      changeCount: 1,
      snapshot: snapshot,
      context: CaptureContext(sourceBundleIdentifier: "com.example.app", now: now),
      settings: settings
    ) == .ignore(.paused)
  )

  settings.pausedUntil = nil
  settings.ignoredApplications = [IgnoredApplication(bundleIdentifier: "com.example.app")]
  var ignored = ClipboardPipeline(lastSeenChangeCount: 0)
  #expect(
    ignored.consume(
      changeCount: 1,
      snapshot: snapshot,
      context: CaptureContext(sourceBundleIdentifier: "com.example.app", now: now),
      settings: settings
    ) == .ignore(.ignoredApplication("com.example.app"))
  )

  settings.ignoredApplications[0].isEnabled = false
  var disabled = ClipboardPipeline(lastSeenChangeCount: 0)
  #expect(
    disabled.consume(
      changeCount: 1,
      snapshot: snapshot,
      context: CaptureContext(sourceBundleIdentifier: "com.example.app", now: now),
      settings: settings
    ) == .process(
      NormalizedClipboard(
        text: "text", kind: .plainText, sourceBundleIdentifier: "com.example.app"))
  )
}

@Test("五种浮层位置都在可见屏幕内并命中预期锚点")
func panelGeometryPlacesEveryMode() {
  let screen = PanelRect(
    origin: PanelPoint(x: 100, y: 50),
    size: PanelSize(width: 1000, height: 700)
  )
  let size = PanelSize(width: 300, height: 160)
  let pointer = PanelPoint(x: 900, y: 650)

  let top = PanelGeometry.frame(
    size: size, pointer: pointer, visibleScreen: screen, placement: .topCenter)
  let center = PanelGeometry.frame(
    size: size, pointer: pointer, visibleScreen: screen, placement: .screenCenter)
  let left = PanelGeometry.frame(
    size: size, pointer: pointer, visibleScreen: screen, placement: .bottomLeft)
  let right = PanelGeometry.frame(
    size: size, pointer: pointer, visibleScreen: screen, placement: .bottomRight)
  let nearPointer = PanelGeometry.frame(
    size: size, pointer: pointer, visibleScreen: screen, placement: .pointer)

  #expect(top.origin == PanelPoint(x: 450, y: 574))
  #expect(center.origin == PanelPoint(x: 450, y: 320))
  #expect(left.origin == PanelPoint(x: 116, y: 66))
  #expect(right.origin == PanelPoint(x: 784, y: 66))
  #expect(nearPointer.maxX <= screen.maxX - 16)
  #expect(nearPointer.maxY <= screen.maxY - 16)
}

@Test("默认关闭策略覆盖全部用户退出路径")
func defaultDismissPolicyCoversEveryExit() {
  let policy = PanelDismissPolicy.default
  #expect(PanelDismissReason.allCases.allSatisfy { policy.shouldDismiss(for: $0) })
}

@Test("旧 settings.json 升级后保留旧值并补齐浮层 icon 默认设置")
func settingsMigrateToGroupedV3() throws {
  let old = """
    {
      "pollIntervalMilliseconds": 750,
      "maxClipboardLength": 2048,
      "panelAutoDismissSeconds": 8,
      "linearWorkspace": "acme",
      "linearTeamKeys": ["MAX"]
    }
    """
  let fs = FakeFileSystem(files: ["/support/settings.json": old])
  let store = Store(fileSystem: fs, directory: "/support")
  let settings = try store.loadSettings()
  let written = try #require(fs.contents(at: "/support/settings.json"))

  #expect(settings.version == Settings.currentVersion)
  #expect(settings.githubSelectedRepositories == nil)
  #expect(settings.listening.pollIntervalMilliseconds == 750)
  #expect(settings.listening.maximumContentLength == 2048)
  #expect(settings.panel.autoDismissSeconds == 8)
  #expect(settings.panel.iconSize == .small)
  #expect(settings.panel.iconStyle == .automatic)
  #expect(settings.linearWorkspace == "acme")
  #expect(written.contains("\"listening\"") && written.contains("\"panel\""))
  #expect(written.contains("panelAutoDismissSeconds") == false)
}

@Test("旧版忽略 Bundle ID 自动迁移为启用的应用列表")
func legacyIgnoredBundleIdentifiersMigrateToApplications() throws {
  let old = """
    {
      "version": 5,
      "listening": {
        "acceptedContentKinds": ["plainText"],
        "repeatIdenticalCopies": true,
        "maximumContentLength": 4096,
        "pollIntervalMilliseconds": 500,
        "ignoredBundleIdentifiers": ["com.example.editor"],
        "launchAtLogin": false,
        "showDockIcon": true
      },
      "panel": {},
      "linearWorkspace": "",
      "linearTeamKeys": []
    }
    """

  let settings = try Store.makeDecoder().decode(Settings.self, from: Data(old.utf8))
  #expect(
    settings.listening.ignoredApplications
      == [IgnoredApplication(bundleIdentifier: "com.example.editor", isEnabled: true)])
  #expect(settings.listening.ignoredBundleIdentifiers == ["com.example.editor"])
}
