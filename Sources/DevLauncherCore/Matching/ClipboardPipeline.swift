import Foundation

public struct PasteboardSnapshot: Equatable, Sendable {
  public var plainText: String?
  public var urlString: String?
  public var filePaths: [String]
  public var richText: String?

  public init(
    plainText: String? = nil,
    urlString: String? = nil,
    filePaths: [String] = [],
    richText: String? = nil
  ) {
    self.plainText = plainText
    self.urlString = urlString
    self.filePaths = filePaths
    self.richText = richText
  }
}

public struct CaptureContext: Equatable, Sendable {
  public var sourceBundleIdentifier: String?
  public var now: Date

  public init(sourceBundleIdentifier: String?, now: Date) {
    self.sourceBundleIdentifier = sourceBundleIdentifier
    self.now = now
  }
}

public enum ClipboardIgnoreReason: Equatable, Sendable {
  case unchangedPasteboard
  case paused
  case ignoredApplication(String)
  case noSupportedRepresentation
  case contentKindDisabled(ClipboardContentKind)
  case empty
  case tooLong(length: Int, limit: Int)
  case repeatedText
}

public enum ClipboardDecision: Equatable, Sendable {
  case process(NormalizedClipboard)
  case ignore(ClipboardIgnoreReason)
}

public struct ClipboardPipeline: Sendable {
  private var lastChangeCount: Int
  private var lastProcessedText: String?

  public init(lastSeenChangeCount: Int) {
    lastChangeCount = lastSeenChangeCount
  }

  public mutating func synchronize(changeCount: Int) {
    lastChangeCount = changeCount
  }

  public mutating func poll(
    source: any PasteboardSource,
    context: () -> CaptureContext,
    settings: ListeningSettings
  ) -> ClipboardDecision {
    let changeCount = source.changeCount
    guard changeCount != lastChangeCount else { return .ignore(.unchangedPasteboard) }
    return consume(
      changeCount: changeCount,
      snapshot: source.snapshot(),
      context: context(),
      settings: settings
    )
  }

  public mutating func consume(
    changeCount: Int,
    snapshot: PasteboardSnapshot,
    context: CaptureContext,
    settings: ListeningSettings
  ) -> ClipboardDecision {
    guard changeCount != lastChangeCount else { return .ignore(.unchangedPasteboard) }
    lastChangeCount = changeCount

    if let pausedUntil = settings.pausedUntil, pausedUntil > context.now {
      return .ignore(.paused)
    }
    if let source = context.sourceBundleIdentifier,
      settings.ignoredBundleIdentifiers.contains(source)
    {
      return .ignore(.ignoredApplication(source))
    }

    guard let normalized = normalize(snapshot, accepted: settings.acceptedContentKinds) else {
      return .ignore(.noSupportedRepresentation)
    }
    let trimmed = normalized.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .ignore(.empty) }
    guard trimmed.count <= settings.maximumContentLength else {
      return .ignore(.tooLong(length: trimmed.count, limit: settings.maximumContentLength))
    }
    if !settings.repeatIdenticalCopies, trimmed == lastProcessedText {
      return .ignore(.repeatedText)
    }
    lastProcessedText = trimmed

    var result = normalized
    result.text = trimmed
    result.sourceBundleIdentifier = context.sourceBundleIdentifier
    return .process(result)
  }

  private func normalize(
    _ snapshot: PasteboardSnapshot,
    accepted: Set<ClipboardContentKind>
  ) -> NormalizedClipboard? {
    if accepted.contains(.file), let path = snapshot.filePaths.first {
      return NormalizedClipboard(text: path, kind: .file)
    }
    if accepted.contains(.url), let value = snapshot.urlString ?? webURL(from: snapshot.plainText) {
      return NormalizedClipboard(text: value, kind: .url)
    }
    if accepted.contains(.plainText), let text = snapshot.plainText {
      return NormalizedClipboard(text: text, kind: .plainText)
    }
    if accepted.contains(.richText), let text = snapshot.richText {
      return NormalizedClipboard(text: text, kind: .richText)
    }
    return nil
  }

  private func webURL(from text: String?) -> String? {
    guard let text,
      let components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
      components.scheme == "http" || components.scheme == "https",
      components.host != nil
    else { return nil }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
