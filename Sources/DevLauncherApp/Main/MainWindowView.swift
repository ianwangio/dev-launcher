import DevLauncherCore
import SwiftUI

struct MainWindowView: View {
  @Bindable var model: AppModel
  @State private var route: AppRoute = .rules

  var body: some View {
    HSplitView {
      AppSidebar(route: $route)
        .frame(minWidth: 168, idealWidth: 184, maxWidth: 200)

      ZStack {
        routeLayer(.rules) { RuleWorkbenchView(model: model) }
        routeLayer(.integrations) { IntegrationsView(model: model) }
        routeLayer(.panel) { PopupSettingsView(model: model) }
        routeLayer(.listening) { ListeningSettingsView(model: model) }
        routeLayer(.activity) { ActivityView(model: model) }
        routeLayer(.statistics) { StatisticsView(model: model) }
      }
      .frame(minWidth: 880, maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(minWidth: 1080, minHeight: 640)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        ListeningToolbarControl(model: model)
          .padding(.trailing, 14)
      }
      .sharedBackgroundVisibility(.hidden)
    }
    .onReceive(NotificationCenter.default.publisher(for: .devLauncherNavigate)) { notification in
      guard let rawValue = notification.object as? String,
        let destination = AppRoute(rawValue: rawValue)
      else { return }
      route = destination
    }
  }

  private func routeLayer<Content: View>(
    _ destination: AppRoute,
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .opacity(route == destination ? 1 : 0)
      .allowsHitTesting(route == destination)
      .accessibilityHidden(route != destination)
      .zIndex(route == destination ? 1 : 0)
  }
}

private struct ListeningToolbarControl: View {
  @Bindable var model: AppModel

  var body: some View {
    Button {
      if model.isListening {
        model.pauseUntilResumed()
      } else {
        model.resumeListening()
      }
    } label: {
      HStack(spacing: 8) {
        Text(model.listeningStatusTitle)
          .font(.system(size: 13, weight: .medium))
        ZStack {
          Capsule(style: .continuous)
            .fill(model.isListening ? Color.green : Color.secondary.opacity(0.35))
          Circle()
            .fill(.white)
            .padding(2)
            .offset(x: model.isListening ? 6.5 : -6.5)
            .shadow(color: .black.opacity(0.16), radius: 1, y: 0.5)
        }
        .frame(width: 30, height: 17)
        .animation(.easeOut(duration: 0.14), value: model.isListening)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(model.isListening ? "暂停监听" : "恢复监听")
    .accessibilityLabel(model.isListening ? "监听中，暂停监听" : "已暂停，恢复监听")
  }
}

extension Notification.Name {
  static let devLauncherNavigate = Notification.Name("DevLauncher.navigate")
}

enum AppRoute: String, CaseIterable, Identifiable {
  case rules
  case integrations
  case panel
  case listening
  case activity
  case statistics

  var id: String { rawValue }

  var title: String {
    switch self {
    case .rules: "规则"
    case .integrations: "集成"
    case .panel: "浮层"
    case .listening: "监听"
    case .activity: "活动"
    case .statistics: "统计"
    }
  }

  var symbol: String {
    switch self {
    case .rules: "doc.text"
    case .integrations: "shippingbox"
    case .panel: "square.3.layers.3d"
    case .listening: "waveform"
    case .activity: "clock"
    case .statistics: "chart.bar.xaxis"
    }
  }

  var shortcut: KeyEquivalent {
    switch self {
    case .rules: "1"
    case .integrations: "2"
    case .panel: "3"
    case .listening: "4"
    case .activity: "5"
    case .statistics: "6"
    }
  }
}

private struct AppSidebar: View {
  @Binding var route: AppRoute

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "bolt.fill")
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 32, height: 32)
          .background(.black, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        Text("DevLauncher")
          .font(.headline)
      }
      .padding(.horizontal, 14)
      .padding(.top, 16)
      .padding(.bottom, 18)

      VStack(spacing: 5) {
        ForEach(AppRoute.allCases) { item in
          SidebarRouteButton(item: item, selection: $route)
        }
      }
      .padding(.horizontal, 9)

      Spacer()

      Button {
        if route != .listening { route = .listening }
      } label: {
        Label("设置", systemImage: "gearshape")
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 11)
          .padding(.vertical, 9)
      }
      .buttonStyle(.plain)
      .contentShape(Rectangle())
      .padding(9)
    }
    .background(.ultraThinMaterial)
  }
}

private struct SidebarRouteButton: View {
  let item: AppRoute
  @Binding var selection: AppRoute
  @State private var isHovering = false

  private var isSelected: Bool { selection == item }

  var body: some View {
    Button {
      guard !isSelected else { return }
      selection = item
    } label: {
      Label(item.title, systemImage: item.symbol)
        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(
          backgroundColor,
          in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .keyboardShortcut(item.shortcut, modifiers: .command)
    .accessibilityLabel(item.title)
    .onHover { isHovering = $0 }
    .animation(.easeOut(duration: 0.12), value: isHovering)
  }

  private var backgroundColor: Color {
    if isSelected { return .accentColor }
    if isHovering { return Color.primary.opacity(0.08) }
    return .clear
  }
}
