import AppKit
import DevLauncherCore
import SwiftUI

enum UISpacing {
  static let xSmall: CGFloat = 4
  static let small: CGFloat = 8
  static let medium: CGFloat = 12
  static let large: CGFloat = 16
  static let xLarge: CGFloat = 24
}

enum UISize {
  static let formControlHeight: CGFloat = 32
  static let auxiliaryRowHeight: CGFloat = 24
  static let compactButton: CGFloat = 28
  static let switchWidth: CGFloat = 40
  static let switchHeight: CGFloat = 24
  static let ruleIcon: CGFloat = 36
  static let ruleRow: CGFloat = 56
  static let fieldColumn: CGFloat = 160
  static let operationColumn: CGFloat = 132
}

struct UIEnableToggle: View {
  var title: String?
  var accessibilityName: String?
  @Binding var isOn: Bool

  init(
    _ title: String? = nil,
    accessibilityLabel: String? = nil,
    isOn: Binding<Bool>
  ) {
    self.title = title
    self.accessibilityName = accessibilityLabel
    _isOn = isOn
  }

  var body: some View {
    HStack(spacing: UISpacing.small) {
      if let title {
        Text(title)
          .font(.callout)
      }
      Toggle(title ?? "启用", isOn: $isOn)
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
        .frame(width: UISize.switchWidth, height: UISize.switchHeight)
        .accessibilityLabel(accessibilityName ?? title ?? "启用")
    }
    .frame(height: UISize.formControlHeight)
  }
}

struct UIOverflowMenu<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    Menu {
      content
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 13, weight: .semibold))
        .frame(width: UISize.compactButton, height: UISize.compactButton)
        .contentShape(Rectangle())
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .accessibilityLabel("更多操作")
  }
}

struct UIIconButton: View {
  let symbol: String
  let label: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .semibold))
        .frame(width: UISize.compactButton, height: UISize.compactButton)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .help(label)
    .accessibilityLabel(label)
  }
}

struct UISectionHeading: View {
  let title: String
  let subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: UISpacing.xSmall) {
      Text(title)
        .font(.headline)
      Text(subtitle)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct UIControlLabel: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.callout.weight(.medium))
      .foregroundStyle(.secondary)
      .frame(width: UISize.fieldColumn, alignment: .trailing)
      .frame(height: UISize.formControlHeight)
  }
}

struct UICheckbox: View {
  let title: String
  @Binding var isOn: Bool

  var body: some View {
    Toggle(title, isOn: $isOn)
      .toggleStyle(.checkbox)
      .controlSize(.small)
      .font(.caption)
      .frame(height: UISize.auxiliaryRowHeight)
  }
}

struct UIActionIcon: View {
  let icon: CandidateIcon
  var pointSize: CGFloat = 18
  var style: PanelIconStyle = .automatic

  var body: some View {
    Group {
      switch icon {
      case .system(let symbolName):
        Image(systemName: symbolName)
          .font(.system(size: pointSize, weight: .semibold))
          .foregroundStyle(symbolColor)
      case .application(let name):
        if let image = ApplicationIconProvider.icon(named: name) {
          Image(nsImage: image)
            .renderingMode(style == .monochrome ? .template : .original)
            .resizable()
            .scaledToFit()
            .foregroundStyle(style == .monochrome ? Color.secondary : Color.primary)
            .frame(width: pointSize, height: pointSize)
        } else {
          if name == "Linear" || name == "GitHub Desktop" {
            UIBrandFallback(name: name, pointSize: pointSize)
          } else {
            Image(systemName: "app")
              .font(.system(size: pointSize, weight: .semibold))
              .foregroundStyle(symbolColor)
          }
        }
      }
    }
    .frame(width: max(24, pointSize + 8), height: max(24, pointSize + 8))
    .background(
      style == .tintedTile ? Color.accentColor.opacity(0.13) : Color.clear,
      in: RoundedRectangle(cornerRadius: 7)
    )
    .accessibilityHidden(true)
  }

  private var symbolColor: Color {
    switch style {
    case .automatic: .primary
    case .monochrome: .secondary
    case .tintedTile: .accentColor
    }
  }
}

private struct UIBrandFallback: View {
  let name: String
  let pointSize: CGFloat

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: max(5, pointSize * 0.24), style: .continuous)
        .fill(name == "Linear" ? Color.indigo.gradient : Color.black.gradient)
      if name == "Linear" {
        VStack(spacing: max(1.2, pointSize * 0.07)) {
          Capsule().frame(width: pointSize * 0.52, height: max(1.5, pointSize * 0.08))
          Capsule().frame(width: pointSize * 0.38, height: max(1.5, pointSize * 0.08))
          Capsule().frame(width: pointSize * 0.23, height: max(1.5, pointSize * 0.08))
        }
        .foregroundStyle(.white)
        .rotationEffect(.degrees(-45))
      } else {
        Image(systemName: "chevron.left.forwardslash.chevron.right")
          .font(.system(size: pointSize * 0.48, weight: .bold))
          .foregroundStyle(.white)
      }
    }
    .frame(width: pointSize, height: pointSize)
  }
}
