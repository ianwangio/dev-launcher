import AppKit
import DevLauncherCore

/// DevLauncher 的常驻入口。菜单在每次展开时重建，状态和暂停剩余时间不会过期。
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
  private let model: AppModel
  private let statusItem: NSStatusItem
  private let openSettings: () -> Void
  private var refreshTimer: Timer?
  private var lastListeningState: Bool

  init(model: AppModel, openSettings: @escaping () -> Void) {
    self.model = model
    self.openSettings = openSettings
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    self.lastListeningState = model.isListening
    super.init()

    let menu = NSMenu(title: "DevLauncher")
    menu.delegate = self
    statusItem.menu = menu
    updateStatusItem()
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.updateStatusItem() }
    }
  }

  func refresh() {
    updateStatusItem()
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()

    let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
    status.image = NSImage(systemSymbolName: model.isListening ? "circle.fill" : "pause.circle.fill", accessibilityDescription: nil)
    status.isEnabled = false
    menu.addItem(status)
    menu.addItem(.separator())

    if model.isListening {
      let pause = NSMenuItem(title: "暂停监听", action: nil, keyEquivalent: "")
      let submenu = NSMenu(title: "暂停监听")
      submenu.addItem(actionItem("暂停 10 分钟", action: #selector(pauseTenMinutes)))
      submenu.addItem(actionItem("暂停 1 小时", action: #selector(pauseOneHour)))
      submenu.addItem(actionItem("直到手动恢复", action: #selector(pauseUntilResumed)))
      pause.submenu = submenu
      menu.addItem(pause)
    } else {
      menu.addItem(actionItem("立即恢复监听", action: #selector(resumeListening)))
    }

    menu.addItem(.separator())
    let launch = actionItem("开机时启动", action: #selector(toggleLaunchAtLogin))
    launch.state = model.settings.listening.launchAtLogin ? .on : .off
    menu.addItem(launch)

    let dock = actionItem("显示 Dock 图标", action: #selector(toggleDockIcon))
    dock.state = model.settings.listening.showDockIcon ? .on : .off
    menu.addItem(dock)

    menu.addItem(.separator())
    menu.addItem(actionItem("打开 DevLauncher…", action: #selector(openSettingsWindow), key: ","))
    menu.addItem(.separator())
    menu.addItem(actionItem("退出 DevLauncher", action: #selector(quit), key: "q"))
  }

  private var statusTitle: String {
    guard !model.isListening, let date = model.settings.listening.pausedUntil else {
      return "监听中"
    }
    if date.timeIntervalSinceNow > 60 * 60 * 24 * 30 {
      return "已暂停 · 直到手动恢复"
    }
    let remaining = max(0, Int(date.timeIntervalSinceNow.rounded(.up)))
    if remaining >= 3600 {
      return "已暂停 · 剩余 \(remaining / 3600) 小时 \((remaining % 3600) / 60) 分"
    }
    return "已暂停 · 剩余 \(max(1, remaining / 60)) 分钟"
  }

  private func updateStatusItem() {
    let currentListeningState = model.isListening
    if currentListeningState != lastListeningState {
      lastListeningState = currentListeningState
      model.refreshListeningStatus()
    }
    guard let button = statusItem.button else { return }
    button.image = NSImage(
      systemSymbolName: model.isListening ? "bolt.circle.fill" : "pause.circle.fill",
      accessibilityDescription: statusTitle
    )
    button.image?.isTemplate = true
    button.toolTip = "DevLauncher · \(statusTitle)"
    button.setAccessibilityLabel("DevLauncher，\(statusTitle)")
  }

  private func actionItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.target = self
    return item
  }

  @objc private func pauseTenMinutes() { pause(seconds: 10 * 60) }
  @objc private func pauseOneHour() { pause(seconds: 60 * 60) }
  @objc private func pauseUntilResumed() {
    model.pauseUntilResumed()
    updateStatusItem()
  }

  private func pause(seconds: Double) {
    model.pauseListening(seconds: seconds)
    updateStatusItem()
  }

  @objc private func resumeListening() {
    model.resumeListening()
    updateStatusItem()
  }

  @objc private func toggleLaunchAtLogin() {
    var settings = model.settings.listening
    settings.launchAtLogin.toggle()
    model.updateListeningSettings(settings)
  }

  @objc private func toggleDockIcon() {
    var settings = model.settings.listening
    settings.showDockIcon.toggle()
    model.updateListeningSettings(settings)
  }

  @objc private func openSettingsWindow() { openSettings() }
  @objc private func quit() { NSApp.terminate(nil) }
}
