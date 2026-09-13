import AppKit
import DevLauncherCore
import SwiftUI

/// 菜单栏常驻应用；设置可决定是否同时显示 Dock 图标。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let model = AppModel()
  private let systemBehavior = SystemBehaviorAdapter()
  private var window: NSWindow?
  private var menuBarController: MenuBarController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    installMainMenu()
    model.onListeningSettingsChanged = { [weak self] settings in
      self?.applySystemBehavior(settings)
    }
    applySystemBehavior(model.settings.listening)
    model.start()
    makeWindow()
    menuBarController = MenuBarController(model: model) { [weak self] in
      self?.makeWindow()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    model.stop()
  }

  /// 关掉主窗口不退出 —— 监听要继续跑。点 Dock 图标重新打开。
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    if !flag { makeWindow() }
    return true
  }

  private func makeWindow() {
    if let window {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let hosting = NSHostingController(rootView: MainWindowView(model: model))
    let window = NSWindow(contentViewController: hosting)
    window.title = "DevLauncher"
    window.setContentSize(NSSize(width: 1280, height: 760))
    window.minSize = NSSize(width: 1080, height: 640)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.center()
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    self.window = window
    NSApp.activate(ignoringOtherApps: true)
  }

  private func applySystemBehavior(_ settings: ListeningSettings) {
    systemBehavior.setDockIconVisible(settings.showDockIcon)
    do {
      try systemBehavior.setLaunchAtLogin(settings.launchAtLogin)
      model.reportSystemBehaviorError(nil)
    } catch {
      model.reportSystemBehaviorError("开机启动设置失败：\(error.localizedDescription)")
    }
    menuBarController?.refresh()
  }

  private func installMainMenu() {
    let mainMenu = NSMenu()

    let applicationItem = NSMenuItem()
    let applicationMenu = NSMenu(title: "DevLauncher")
    applicationMenu.addItem(
      NSMenuItem(title: "关于 DevLauncher", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    )
    applicationMenu.addItem(.separator())
    let settingsItem = NSMenuItem(title: "打开 DevLauncher…", action: #selector(openSettingsFromMainMenu), keyEquivalent: ",")
    settingsItem.target = self
    applicationMenu.addItem(settingsItem)
    applicationMenu.addItem(.separator())
    applicationMenu.addItem(
      NSMenuItem(
        title: "退出 DevLauncher",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
      )
    )
    applicationItem.submenu = applicationMenu
    mainMenu.addItem(applicationItem)

    let editItem = NSMenuItem()
    let editMenu = NSMenu(title: "编辑")
    editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
    editMenu.addItem(NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z"))
    editMenu.addItem(.separator())
    editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
    editMenu.addItem(
      NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
    editMenu.addItem(
      NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
    editMenu.addItem(
      NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
    editItem.submenu = editMenu
    mainMenu.addItem(editItem)

    let viewItem = NSMenuItem()
    let viewMenu = NSMenu(title: "显示")
    for (index, route) in AppRoute.allCases.enumerated() {
      let item = NSMenuItem(
        title: route.title,
        action: #selector(navigateFromMainMenu(_:)),
        keyEquivalent: String(index + 1)
      )
      item.target = self
      item.representedObject = route.rawValue
      viewMenu.addItem(item)
    }
    viewItem.submenu = viewMenu
    mainMenu.addItem(viewItem)

    NSApp.mainMenu = mainMenu
  }

  @objc private func openSettingsFromMainMenu() {
    makeWindow()
  }

  @objc private func navigateFromMainMenu(_ sender: NSMenuItem) {
    makeWindow()
    guard let route = sender.representedObject as? String else { return }
    NotificationCenter.default.post(name: .devLauncherNavigate, object: route)
  }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
