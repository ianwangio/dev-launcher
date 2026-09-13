import DevLauncherCore
import Foundation
import Testing

@Test("最终设置编码往返保留登录启动、Dock 和浮层外观")
func finalSettingsRoundTrip() throws {
  var expected = Settings.default
  expected.listening.launchAtLogin = true
  expected.listening.showDockIcon = false
  expected.listening.pausedUntil = Date(timeIntervalSince1970: 1_800_000_000)
  expected.panel.placement = .bottomRight
  expected.panel.appearance = .dark
  expected.panel.density = .compact

  let encoded = try Store.makeEncoder().encode(expected)
  let decoded = try Store.makeDecoder().decode(Settings.self, from: encoded)

  #expect(decoded == expected)
}

@Test("菜单栏提供状态、三种暂停、设置和退出入口")
func menuBarHasCompleteDailyControls() throws {
  let path = SourceTree.root + "/Sources/DevLauncherApp/Main/MenuBarView.swift"
  let source = try String(contentsOfFile: path, encoding: .utf8)

  for requiredText in [
    "监听中", "暂停 10 分钟", "暂停 1 小时", "直到手动恢复",
    "立即恢复监听", "开机时启动", "显示 Dock 图标", "打开 DevLauncher…", "退出 DevLauncher",
  ] {
    #expect(source.contains(requiredText), "菜单栏缺少：\(requiredText)")
  }
  #expect(source.contains("setAccessibilityLabel"), "菜单栏状态项缺少 VoiceOver label")
}

@Test("窗口右上角监听开关不使用共享玻璃胶囊并保留安全间距")
func listeningToolbarToggleHasNoSharedBackground() throws {
  let path = SourceTree.root + "/Sources/DevLauncherApp/Main/MainWindowView.swift"
  let source = try String(contentsOfFile: path, encoding: .utf8)

  #expect(source.contains(".sharedBackgroundVisibility(.hidden)"))
  #expect(source.contains(".frame(width: 30, height: 17)"))
  #expect(source.contains(".padding(.trailing, 14)"))
}

@Test("主导航复用页面并为左侧菜单提供轻量 hover 反馈")
func sidebarNavigationAvoidsPageReconstruction() throws {
  let path = SourceTree.root + "/Sources/DevLauncherApp/Main/MainWindowView.swift"
  let source = try String(contentsOfFile: path, encoding: .utf8)

  #expect(source.contains("ZStack"))
  #expect(source.contains("routeLayer(.integrations)"))
  #expect(source.contains(".allowsHitTesting(route == destination)"))
  #expect(source.contains(".onHover { isHovering = $0 }"))
}

@Test("Release 应用包含完整 macOS 图标资源")
func releaseBundleIncludesApplicationIcon() throws {
  let scriptPath = SourceTree.root + "/Scripts/build-app.sh"
  let source = try String(contentsOfFile: scriptPath, encoding: .utf8)
  let iconPath = SourceTree.root + "/Assets/DevLauncher-AppIcon-1024.png"

  #expect(FileManager.default.fileExists(atPath: iconPath))
  #expect(source.contains("iconutil --convert icns"))
  #expect(source.contains("DevLauncher.icns"))
  #expect(source.contains("CFBundleIconFile"))
}

@Test("忽略应用通过多选文件面板加入并使用列表前置复选框")
func ignoredApplicationsUsePickerAndCheckboxSelection() throws {
  let path = SourceTree.root + "/Sources/DevLauncherApp/Main/ListeningSettingsView.swift"
  let source = try String(contentsOfFile: path, encoding: .utf8)
  let adapterPath = SourceTree.root + "/Sources/DevLauncherApp/Adapters/SystemAdapters.swift"
  let adapter = try String(contentsOfFile: adapterPath, encoding: .utf8)

  #expect(source.contains("选择应用…"))
  #expect(source.contains(".toggleStyle(.checkbox)"))
  #expect(source.contains("应用 Bundle ID，例如") == false)
  #expect(adapter.contains("panel.directoryURL = URL(fileURLWithPath: \"/Applications\""))
  #expect(adapter.contains("panel.allowsMultipleSelection = true"))
  #expect(adapter.contains("panel.allowedContentTypes = [.applicationBundle]"))
}

@Test("浮层位置卡片的完整视觉区域都是点击目标")
func placementCardsUseFullHitArea() throws {
  let path = SourceTree.root + "/Sources/DevLauncherApp/Main/PopupSettingsView.swift"
  let source = try String(contentsOfFile: path, encoding: .utf8)

  #expect(source.contains(".contentShape(Rectangle())"))
}

@Test("系统启动与 Dock 副作用只由 Adapter 承担")
func systemBehaviorLivesBehindAdapter() {
  let appLines = SourceTree.lines(under: "Sources/DevLauncherApp")
  let offenders = SourceTree.matches(
    appLines,
    pattern: #"SMAppService|setActivationPolicy\("#
  ).filter { !$0.path.contains("/Adapters/") && !$0.path.hasSuffix("main.swift") }

  #expect(offenders.isEmpty, "系统启动行为越过 Adapter：\(offenders.map(\.location))")
}

@Test("共享紧凑控件不小于 macOS 常用点击目标")
func sharedCompactControlsHaveUsableTarget() throws {
  let path = SourceTree.root + "/Sources/DevLauncherApp/DesignSystem/UIFoundation.swift"
  let source = try String(contentsOfFile: path, encoding: .utf8)
  let pattern = #"static let compactButton: CGFloat = ([0-9]+)"#
  let expression = try NSRegularExpression(pattern: pattern)
  let range = NSRange(source.startIndex..<source.endIndex, in: source)
  let match = try #require(expression.firstMatch(in: source, range: range))
  let valueRange = try #require(Range(match.range(at: 1), in: source))
  let value = try #require(Int(source[valueRange]))

  #expect(value >= 28)
}

@Test("统计页包含已验收的年度日历、月度悬浮信息和独立详情区")
func statisticsPageMatchesAcceptedPrototype() throws {
  let mainPath = SourceTree.root + "/Sources/DevLauncherApp/Main/MainWindowView.swift"
  let mainSource = try String(contentsOfFile: mainPath, encoding: .utf8)
  let pagePath = SourceTree.root + "/Sources/DevLauncherApp/Main/StatisticsView.swift"
  let pageSource = try String(contentsOfFile: pagePath, encoding: .utf8)

  #expect(mainSource.contains("routeLayer(.statistics)"))
  #expect(mainSource.contains("case statistics"))
  for requiredText in [
    "统计概览", "最近一年", "活动聚合", "全年按周横向排列", "按日", "按月",
    "当日详情", "当月详情", "常用动作", "聚合统计不包含剪贴板内容",
  ] {
    #expect(pageSource.contains(requiredText), "统计页缺少：\(requiredText)")
  }
  #expect(pageSource.contains("onHover"), "月度图缺少悬浮详情")
  #expect(pageSource.contains("LazyHGrid"), "按日视图不是年度周列热力图")
}
