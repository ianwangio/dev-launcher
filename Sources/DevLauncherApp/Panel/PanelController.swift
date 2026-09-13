import AppKit
import DevLauncherCore
import SwiftUI

@MainActor
final class PanelController {
  private var panel: NSPanel?
  private var dismissTimer: Timer?
  private var escapeMonitor: Any?
  private var localMouseMonitor: Any?
  private var globalMouseMonitor: Any?
  private var isHovering = false
  private var settings = PanelSettings.default

  private let onActivate: (Candidate) -> Void

  init(onActivate: @escaping (Candidate) -> Void) {
    self.onActivate = onActivate
  }

  func show(candidates: [Candidate], settings: PanelSettings) {
    guard !candidates.isEmpty else { return }
    hide()
    self.settings = settings

    let visibleCandidates = Array(candidates.prefix(max(1, settings.maximumCandidates)))
    let panel = existingOrNewPanel()
    let view = PanelView(
      candidates: visibleCandidates,
      density: settings.density,
      iconSize: settings.iconSize,
      iconStyle: settings.iconStyle,
      onActivate: { [weak self] candidate in
        guard let self else { return }
        if self.settings.dismissPolicy.actionActivation { self.hide() }
        self.onActivate(candidate)
      },
      onHoverChange: { [weak self] hovering in
        guard let self else { return }
        self.isHovering = hovering
        if hovering && self.settings.dismissPolicy.pauseTimeoutWhileHovering {
          self.dismissTimer?.invalidate()
        } else {
          self.scheduleDismiss()
        }
      }
    )
    .preferredColorScheme(colorScheme(for: settings.appearance))

    let hosting = NSHostingView(rootView: view)
    hosting.layout()
    let size = hosting.fittingSize
    panel.contentView = hosting
    panel.setFrame(
      Self.frame(
        forSize: size,
        near: NSEvent.mouseLocation,
        placement: settings.placement
      ),
      display: true
    )
    panel.orderFrontRegardless()

    installEscapeMonitor()
    installOutsideClickMonitors()
    scheduleDismiss()
  }

  func hide() {
    dismissTimer?.invalidate()
    dismissTimer = nil
    isHovering = false
    removeMonitors()
    panel?.orderOut(nil)
  }

  static func frame(
    forSize size: NSSize,
    near mouse: NSPoint,
    placement: PanelPlacement = .pointer
  ) -> NSRect {
    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let result = PanelGeometry.frame(
      size: PanelSize(width: size.width, height: size.height),
      pointer: PanelPoint(x: mouse.x, y: mouse.y),
      visibleScreen: PanelRect(
        origin: PanelPoint(x: visible.minX, y: visible.minY),
        size: PanelSize(width: visible.width, height: visible.height)
      ),
      placement: placement,
      gap: PanelMetrics.cursorGap
    )
    return NSRect(
      x: result.origin.x,
      y: result.origin.y,
      width: result.size.width,
      height: result.size.height
    )
  }

  private func existingOrNewPanel() -> NSPanel {
    if let panel { return panel }

    let panel = NSPanel(
      contentRect: NSRect(
        x: 0,
        y: 0,
        width: PanelMetrics.width,
        height: PanelMetrics.comfortableRow + PanelMetrics.padding * 2
      ),
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered,
      defer: false
    )
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.isFloatingPanel = true
    panel.becomesKeyOnlyIfNeeded = true
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isMovable = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    self.panel = panel
    return panel
  }

  private func scheduleDismiss() {
    dismissTimer?.invalidate()
    guard settings.dismissPolicy.timeout else { return }
    guard !(isHovering && settings.dismissPolicy.pauseTimeoutWhileHovering) else { return }
    dismissTimer = Timer.scheduledTimer(
      withTimeInterval: max(0.5, settings.autoDismissSeconds),
      repeats: false
    ) { [weak self] _ in
      Task { @MainActor in self?.hide() }
    }
  }

  private func installEscapeMonitor() {
    guard settings.dismissPolicy.escape, escapeMonitor == nil else { return }
    escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard event.keyCode == 53 else { return event }
      Task { @MainActor in self?.hide() }
      return nil
    }
  }

  private func installOutsideClickMonitors() {
    guard settings.dismissPolicy.outsideClick else { return }
    let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
      guard let self, let panel = self.panel else { return event }
      if !panel.frame.contains(NSEvent.mouseLocation) {
        Task { @MainActor in self.hide() }
      }
      return event
    }
    globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
      Task { @MainActor in self?.hide() }
    }
  }

  private func removeMonitors() {
    for monitor in [escapeMonitor, localMouseMonitor, globalMouseMonitor].compactMap({ $0 }) {
      NSEvent.removeMonitor(monitor)
    }
    escapeMonitor = nil
    localMouseMonitor = nil
    globalMouseMonitor = nil
  }

  private func colorScheme(for appearance: PanelAppearance) -> ColorScheme? {
    switch appearance {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}
