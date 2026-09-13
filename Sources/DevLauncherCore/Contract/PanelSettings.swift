import Foundation

public enum PanelPlacement: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
  case pointer
  case topCenter
  case screenCenter
  case bottomLeft
  case bottomRight

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .pointer: "鼠标附近"
    case .topCenter: "屏幕顶部中央"
    case .screenCenter: "屏幕中央"
    case .bottomLeft: "左下角"
    case .bottomRight: "右下角"
    }
  }
}

public enum PanelDensity: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
  case comfortable
  case compact

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .comfortable: "舒适"
    case .compact: "紧凑"
    }
  }
}

public enum PanelIconSize: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
  case small
  case medium
  case large

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .small: "小"
    case .medium: "中"
    case .large: "大"
    }
  }
}

public enum PanelIconStyle: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
  case automatic
  case monochrome
  case tintedTile

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .automatic: "自动彩色"
    case .monochrome: "单色"
    case .tintedTile: "淡色底板"
    }
  }
}

public enum PanelAppearance: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
  case system
  case light
  case dark

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .system: "跟随系统"
    case .light: "浅色"
    case .dark: "深色"
    }
  }
}

public struct PanelDismissPolicy: Codable, Equatable, Sendable {
  public var outsideClick: Bool
  public var actionActivation: Bool
  public var newClipboard: Bool
  public var escape: Bool
  public var timeout: Bool
  public var pauseTimeoutWhileHovering: Bool

  public static let `default` = PanelDismissPolicy(
    outsideClick: true,
    actionActivation: true,
    newClipboard: true,
    escape: true,
    timeout: true,
    pauseTimeoutWhileHovering: true
  )

  public init(
    outsideClick: Bool,
    actionActivation: Bool,
    newClipboard: Bool,
    escape: Bool,
    timeout: Bool,
    pauseTimeoutWhileHovering: Bool
  ) {
    self.outsideClick = outsideClick
    self.actionActivation = actionActivation
    self.newClipboard = newClipboard
    self.escape = escape
    self.timeout = timeout
    self.pauseTimeoutWhileHovering = pauseTimeoutWhileHovering
  }

  public func shouldDismiss(for reason: PanelDismissReason) -> Bool {
    switch reason {
    case .outsideClick: outsideClick
    case .actionActivation: actionActivation
    case .newClipboard: newClipboard
    case .escape: escape
    case .timeout: timeout
    case .pause, .applicationStop: true
    }
  }
}

public enum PanelDismissReason: String, Codable, CaseIterable, Equatable, Sendable {
  case outsideClick
  case actionActivation
  case newClipboard
  case escape
  case timeout
  case pause
  case applicationStop
}

public struct PanelSettings: Codable, Equatable, Sendable {
  public var placement: PanelPlacement
  public var dismissPolicy: PanelDismissPolicy
  public var density: PanelDensity
  public var iconSize: PanelIconSize
  public var iconStyle: PanelIconStyle
  public var maximumCandidates: Int
  public var autoDismissSeconds: Double
  public var appearance: PanelAppearance

  public static let `default` = PanelSettings(
    placement: .pointer,
    dismissPolicy: .default,
    density: .comfortable,
    iconSize: .small,
    iconStyle: .automatic,
    maximumCandidates: 8,
    autoDismissSeconds: 5,
    appearance: .system
  )

  public init(
    placement: PanelPlacement,
    dismissPolicy: PanelDismissPolicy,
    density: PanelDensity,
    iconSize: PanelIconSize,
    iconStyle: PanelIconStyle,
    maximumCandidates: Int,
    autoDismissSeconds: Double,
    appearance: PanelAppearance
  ) {
    self.placement = placement
    self.dismissPolicy = dismissPolicy
    self.density = density
    self.iconSize = iconSize
    self.iconStyle = iconStyle
    self.maximumCandidates = maximumCandidates
    self.autoDismissSeconds = autoDismissSeconds
    self.appearance = appearance
  }

  private enum CodingKeys: String, CodingKey {
    case placement
    case dismissPolicy
    case density
    case iconSize
    case iconStyle
    case maximumCandidates
    case autoDismissSeconds
    case appearance
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    placement = try container.decodeIfPresent(PanelPlacement.self, forKey: .placement) ?? .pointer
    dismissPolicy =
      try container.decodeIfPresent(PanelDismissPolicy.self, forKey: .dismissPolicy) ?? .default
    density = try container.decodeIfPresent(PanelDensity.self, forKey: .density) ?? .comfortable
    iconSize = try container.decodeIfPresent(PanelIconSize.self, forKey: .iconSize) ?? .small
    iconStyle = try container.decodeIfPresent(PanelIconStyle.self, forKey: .iconStyle) ?? .automatic
    maximumCandidates = try container.decodeIfPresent(Int.self, forKey: .maximumCandidates) ?? 8
    autoDismissSeconds =
      try container.decodeIfPresent(Double.self, forKey: .autoDismissSeconds) ?? 5
    appearance = try container.decodeIfPresent(PanelAppearance.self, forKey: .appearance) ?? .system
  }
}

public struct IgnoredApplication: Codable, Equatable, Sendable, Identifiable {
  public var bundleIdentifier: String
  public var isEnabled: Bool

  public var id: String { bundleIdentifier }

  public init(bundleIdentifier: String, isEnabled: Bool = true) {
    self.bundleIdentifier = bundleIdentifier
    self.isEnabled = isEnabled
  }
}

public struct ListeningSettings: Codable, Equatable, Sendable {
  public var acceptedContentKinds: Set<ClipboardContentKind>
  public var repeatIdenticalCopies: Bool
  public var maximumContentLength: Int
  public var pollIntervalMilliseconds: Int
  public var ignoredApplications: [IgnoredApplication]
  public var pausedUntil: Date?
  public var launchAtLogin: Bool
  public var showDockIcon: Bool

  public var ignoredBundleIdentifiers: [String] {
    ignoredApplications.filter(\.isEnabled).map(\.bundleIdentifier)
  }

  public static let `default` = ListeningSettings(
    acceptedContentKinds: [.plainText, .url, .file, .richText],
    repeatIdenticalCopies: true,
    maximumContentLength: 4096,
    pollIntervalMilliseconds: 500,
    ignoredApplications: [],
    pausedUntil: nil,
    launchAtLogin: false,
    showDockIcon: true
  )

  public init(
    acceptedContentKinds: Set<ClipboardContentKind>,
    repeatIdenticalCopies: Bool,
    maximumContentLength: Int,
    pollIntervalMilliseconds: Int,
    ignoredApplications: [IgnoredApplication],
    pausedUntil: Date?,
    launchAtLogin: Bool,
    showDockIcon: Bool
  ) {
    self.acceptedContentKinds = acceptedContentKinds
    self.repeatIdenticalCopies = repeatIdenticalCopies
    self.maximumContentLength = maximumContentLength
    self.pollIntervalMilliseconds = pollIntervalMilliseconds
    self.ignoredApplications = ignoredApplications
    self.pausedUntil = pausedUntil
    self.launchAtLogin = launchAtLogin
    self.showDockIcon = showDockIcon
  }

  private enum CodingKeys: String, CodingKey {
    case acceptedContentKinds
    case repeatIdenticalCopies
    case maximumContentLength
    case pollIntervalMilliseconds
    case ignoredApplications
    case ignoredBundleIdentifiers
    case pausedUntil
    case launchAtLogin
    case showDockIcon
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    acceptedContentKinds =
      try container.decodeIfPresent(Set<ClipboardContentKind>.self, forKey: .acceptedContentKinds)
      ?? ListeningSettings.default.acceptedContentKinds
    repeatIdenticalCopies =
      try container.decodeIfPresent(Bool.self, forKey: .repeatIdenticalCopies) ?? true
    maximumContentLength =
      try container.decodeIfPresent(Int.self, forKey: .maximumContentLength) ?? 4096
    pollIntervalMilliseconds =
      try container.decodeIfPresent(Int.self, forKey: .pollIntervalMilliseconds) ?? 500
    if let applications = try container.decodeIfPresent(
      [IgnoredApplication].self, forKey: .ignoredApplications)
    {
      ignoredApplications = applications
    } else {
      ignoredApplications = try container.decodeIfPresent(
        [String].self, forKey: .ignoredBundleIdentifiers
      )?.map { IgnoredApplication(bundleIdentifier: $0) } ?? []
    }
    pausedUntil = try container.decodeIfPresent(Date.self, forKey: .pausedUntil)
    launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
    showDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? true
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(acceptedContentKinds, forKey: .acceptedContentKinds)
    try container.encode(repeatIdenticalCopies, forKey: .repeatIdenticalCopies)
    try container.encode(maximumContentLength, forKey: .maximumContentLength)
    try container.encode(pollIntervalMilliseconds, forKey: .pollIntervalMilliseconds)
    try container.encode(ignoredApplications, forKey: .ignoredApplications)
    try container.encodeIfPresent(pausedUntil, forKey: .pausedUntil)
    try container.encode(launchAtLogin, forKey: .launchAtLogin)
    try container.encode(showDockIcon, forKey: .showDockIcon)
  }
}

public struct PanelPoint: Equatable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

public struct PanelSize: Equatable, Sendable {
  public var width: Double
  public var height: Double

  public init(width: Double, height: Double) {
    self.width = width
    self.height = height
  }
}

public struct PanelRect: Equatable, Sendable {
  public var origin: PanelPoint
  public var size: PanelSize

  public init(origin: PanelPoint, size: PanelSize) {
    self.origin = origin
    self.size = size
  }

  public var maxX: Double { origin.x + size.width }
  public var maxY: Double { origin.y + size.height }
}

public enum PanelGeometry {
  public static func frame(
    size: PanelSize,
    pointer: PanelPoint,
    visibleScreen: PanelRect,
    placement: PanelPlacement,
    gap: Double = 12,
    margin: Double = 16
  ) -> PanelRect {
    let minX = visibleScreen.origin.x + margin
    let minY = visibleScreen.origin.y + margin
    let maxX = visibleScreen.maxX - margin - size.width
    let maxY = visibleScreen.maxY - margin - size.height

    var x: Double
    var y: Double
    switch placement {
    case .pointer:
      x = pointer.x + gap
      if x + size.width > visibleScreen.maxX - margin {
        x = pointer.x - gap - size.width
      }
      y = pointer.y + gap
      if y + size.height > visibleScreen.maxY - margin {
        y = pointer.y - gap - size.height
      }
    case .topCenter:
      x = visibleScreen.origin.x + (visibleScreen.size.width - size.width) / 2
      y = maxY
    case .screenCenter:
      x = visibleScreen.origin.x + (visibleScreen.size.width - size.width) / 2
      y = visibleScreen.origin.y + (visibleScreen.size.height - size.height) / 2
    case .bottomLeft:
      x = minX
      y = minY
    case .bottomRight:
      x = maxX
      y = minY
    }
    x = min(max(x, minX), maxX)
    y = min(max(y, minY), maxY)
    return PanelRect(origin: PanelPoint(x: x, y: y), size: size)
  }
}
