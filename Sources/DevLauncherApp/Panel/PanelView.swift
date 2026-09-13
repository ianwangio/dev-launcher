import AppKit
import DevLauncherCore
import SwiftUI

struct PanelView: View {
  let candidates: [Candidate]
  let density: PanelDensity
  let iconSize: PanelIconSize
  let iconStyle: PanelIconStyle
  let onActivate: (Candidate) -> Void
  let onHoverChange: (Bool) -> Void

  var body: some View {
    VStack(spacing: 2) {
      ForEach(candidates) { candidate in
        CandidateRow(
          candidate: candidate,
          height: density == .comfortable ? PanelMetrics.comfortableRow : PanelMetrics.compactRow,
          iconSize: iconSize,
          iconStyle: iconStyle,
          onActivate: onActivate
        )
      }
    }
    .padding(PanelMetrics.padding)
    .frame(width: PanelMetrics.width)
    .fixedSize(horizontal: true, vertical: true)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
    )
    .onHover(perform: onHoverChange)
  }
}

private struct CandidateRow: View {
  let candidate: Candidate
  let height: CGFloat
  let iconSize: PanelIconSize
  let iconStyle: PanelIconStyle
  let onActivate: (Candidate) -> Void
  @State private var isHovering = false

  var body: some View {
    Button {
      guard candidate.availability.isAvailable else { return }
      onActivate(candidate)
    } label: {
      HStack(spacing: 8) {
        UIActionIcon(icon: candidate.icon, pointSize: pointSize, style: iconStyle)
          .frame(width: 24, height: 24)

        Text(hintText)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(hintColor)
          .lineLimit(1)

        Spacer(minLength: 6)

        if !candidate.availability.isAvailable {
          Image(systemName: "exclamationmark.circle.fill")
            .font(.system(size: 12))
            .foregroundStyle(.orange)
        }
      }
      .padding(.horizontal, 9)
      .frame(height: height)
      .frame(maxWidth: .infinity)
      .background(
        isHovering && candidate.availability.isAvailable
          ? Color.accentColor.opacity(0.18)
          : Color.clear,
        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .opacity(candidate.availability.isAvailable ? 1 : 0.58)
    .onHover { isHovering = $0 }
    .help(helpText)
    .accessibilityLabel(candidate.title)
    .accessibilityHint(candidate.availability.reason ?? candidate.detail)
  }

  private var helpText: String {
    if let reason = candidate.availability.reason {
      return "\(candidate.title) — \(reason)"
    }
    return "\(candidate.title) — \(candidate.detail)"
  }

  private var hintText: String {
    candidate.availability.reason ?? candidate.detail
  }

  private var hintColor: Color {
    candidate.availability.isAvailable ? .secondary : .orange
  }

  private var pointSize: CGFloat {
    switch iconSize {
    case .small: 14
    case .medium: 18
    case .large: 22
    }
  }
}

enum PanelMetrics {
  static let width: CGFloat = 320
  static let comfortableRow: CGFloat = 40
  static let compactRow: CGFloat = 34
  static let padding: CGFloat = 6
  static let cursorGap: CGFloat = 12
}
