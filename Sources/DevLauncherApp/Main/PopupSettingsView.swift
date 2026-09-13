import DevLauncherCore
import SwiftUI

struct PopupSettingsView: View {
  @Bindable var model: AppModel
  @State private var draft: PanelSettings

  init(model: AppModel) {
    self.model = model
    _draft = State(initialValue: model.settings.panel)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: UISpacing.xLarge) {
        header
        Divider()
        placementSection
        Divider()
        dismissSection
        Divider()
        displaySection
        Divider()
        appearanceSection
      }
      .padding(28)
      .frame(maxWidth: 980, alignment: .leading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
    .onChange(of: draft) { _, value in model.updatePanelSettings(value) }
  }

  private var header: some View {
    HStack(spacing: UISpacing.large) {
      Image(systemName: "square.3.layers.3d")
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 52, height: 52)
        .background(.black, in: RoundedRectangle(cornerRadius: 12))
      VStack(alignment: .leading, spacing: UISpacing.xSmall) {
        Text("浮层").font(.title2.weight(.bold))
        Text("配置候选浮层的位置、关闭方式和显示密度。")
          .font(.callout).foregroundStyle(.secondary)
      }
      Spacer()
      Button("在当前屏幕预览", systemImage: "play.fill") { model.previewPanel() }
        .buttonStyle(.borderedProminent)
    }
  }

  private var placementSection: some View {
    VStack(alignment: .leading, spacing: UISpacing.medium) {
      UISectionHeading(title: "出现位置", subtitle: "选择浮层在当前屏幕上的默认位置。")
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: UISpacing.small), count: 5)
      ) {
        ForEach(PanelPlacement.allCases) { placement in
          Button {
            draft.placement = placement
          } label: {
            VStack(spacing: UISpacing.small) {
              PlacementDiagram(placement: placement)
                .frame(height: 66)
              Text(placement.title)
                .font(.caption.weight(draft.placement == placement ? .semibold : .regular))
                .lineLimit(1)
            }
            .padding(UISpacing.small)
            .frame(maxWidth: .infinity)
            .background(
              draft.placement == placement ? Color.accentColor.opacity(0.13) : Color.clear,
              in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay(
              RoundedRectangle(cornerRadius: 9)
                .stroke(
                  draft.placement == placement ? Color.accentColor : Color.secondary.opacity(0.22),
                  lineWidth: draft.placement == placement ? 2 : 1
                )
            )
            // PlainButtonStyle 默认按实际绘制内容命中；显式铺满后，文字、留白和预览区
            // 都属于同一张可点击卡片。
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("浮层位置：\(placement.title)")
          .accessibilityHint(
            draft.placement == placement ? "当前已选择" : "选择并用于下次预览"
          )
        }
      }
    }
  }

  private var dismissSection: some View {
    VStack(alignment: .leading, spacing: UISpacing.medium) {
      UISectionHeading(title: "关闭方式", subtitle: "选择哪些操作会关闭当前浮层。")
      Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: UISpacing.small) {
        GridRow {
          UICheckbox(title: "点击浮层外", isOn: policyBinding(\.outsideClick))
          UICheckbox(title: "执行动作后", isOn: policyBinding(\.actionActivation))
        }
        GridRow {
          UICheckbox(title: "复制新内容后", isOn: policyBinding(\.newClipboard))
          UICheckbox(title: "按下 Esc", isOn: policyBinding(\.escape))
        }
        GridRow {
          UICheckbox(title: "超时自动关闭", isOn: policyBinding(\.timeout))
          UICheckbox(
            title: "鼠标悬停时暂停计时",
            isOn: policyBinding(\.pauseTimeoutWhileHovering)
          )
        }
      }
    }
  }

  private var displaySection: some View {
    VStack(alignment: .leading, spacing: UISpacing.medium) {
      UISectionHeading(title: "显示", subtitle: "控制候选数量、密度和自动关闭时间。")
      Grid(
        alignment: .leading, horizontalSpacing: UISpacing.medium, verticalSpacing: UISpacing.medium
      ) {
        GridRow {
          UIControlLabel(text: "显示密度")
          Picker("显示密度", selection: $draft.density) {
            ForEach(PanelDensity.allCases) { Text($0.title).tag($0) }
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 220, height: UISize.formControlHeight)
        }
        GridRow {
          UIControlLabel(text: "Icon 大小")
          Picker("Icon 大小", selection: $draft.iconSize) {
            ForEach(PanelIconSize.allCases) { Text($0.title).tag($0) }
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 220, height: UISize.formControlHeight)
        }
        GridRow {
          UIControlLabel(text: "Icon 样式")
          Picker("Icon 样式", selection: $draft.iconStyle) {
            ForEach(PanelIconStyle.allCases) { Text($0.title).tag($0) }
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 300, height: UISize.formControlHeight)
        }
        GridRow {
          UIControlLabel(text: "候选项数量")
          Stepper(value: $draft.maximumCandidates, in: 1...20) {
            Text("\(draft.maximumCandidates) 项")
              .monospacedDigit()
          }
          .frame(width: 220, height: UISize.formControlHeight)
        }
        GridRow {
          UIControlLabel(text: "自动关闭时间")
          HStack {
            Slider(value: $draft.autoDismissSeconds, in: 1...20, step: 1)
            Text("\(Int(draft.autoDismissSeconds)) 秒")
              .monospacedDigit()
              .frame(width: 48, alignment: .trailing)
          }
          .frame(maxWidth: 420)
          .frame(height: UISize.formControlHeight)
        }
      }
    }
  }

  private var appearanceSection: some View {
    VStack(alignment: .leading, spacing: UISpacing.medium) {
      UISectionHeading(title: "外观", subtitle: "只影响浮层，不改变主窗口外观。")
      HStack(spacing: UISpacing.medium) {
        UIControlLabel(text: "颜色")
        Picker("颜色", selection: $draft.appearance) {
          ForEach(PanelAppearance.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 300, height: UISize.formControlHeight)
      }
    }
  }

  private func policyBinding(_ keyPath: WritableKeyPath<PanelDismissPolicy, Bool>) -> Binding<Bool>
  {
    Binding {
      draft.dismissPolicy[keyPath: keyPath]
    } set: { value in
      draft.dismissPolicy[keyPath: keyPath] = value
    }
  }
}

private struct PlacementDiagram: View {
  let placement: PanelPlacement

  var body: some View {
    GeometryReader { geometry in
      let size = CGSize(width: 30, height: 15)
      RoundedRectangle(cornerRadius: 5)
        .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
        .overlay(alignment: alignment) {
          RoundedRectangle(cornerRadius: 3)
            .fill(Color.accentColor)
            .frame(width: size.width, height: size.height)
            .padding(6)
        }
        .overlay {
          if placement == .pointer {
            Image(systemName: "cursorarrow")
              .font(.system(size: 17))
              .offset(x: -5, y: 4)
          }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
  }

  private var alignment: Alignment {
    switch placement {
    case .pointer, .screenCenter: .center
    case .topCenter: .top
    case .bottomLeft: .bottomLeading
    case .bottomRight: .bottomTrailing
    }
  }
}
