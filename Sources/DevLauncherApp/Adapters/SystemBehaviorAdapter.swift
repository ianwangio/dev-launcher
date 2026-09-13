import AppKit
import Foundation
import ServiceManagement

/// 菜单栏应用涉及的系统级行为统一放在 Adapter，视图只修改设置。
@MainActor
final class SystemBehaviorAdapter {
  func setDockIconVisible(_ visible: Bool) {
    let policy: NSApplication.ActivationPolicy = visible ? .regular : .accessory
    NSApp.setActivationPolicy(policy)
  }

  func setLaunchAtLogin(_ enabled: Bool) throws {
    let service = SMAppService.mainApp
    if enabled {
      guard service.status != .enabled else { return }
      try service.register()
    } else {
      guard service.status == .enabled else { return }
      try service.unregister()
    }
  }
}
