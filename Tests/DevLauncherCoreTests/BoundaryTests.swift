import DevLauncherCore
import Foundation
import Testing

/// shape.md 3.2 那张边界表的执行体。
///
/// 每条边界都是"越界了什么会失败"。这些检查跟着 `swift test` 走，不需要额外工具，
/// 失败信息直接指到文件和行。代价是可以被刻意绕过 —— 接受，因为边界的作用是防漂移，不是防对抗。
///
/// B1（Core 不依赖 App）不在这里：它由编译器守，Core 里写 `import DevLauncherApp`
/// 会让 `swift build` 报 target 循环依赖。
enum SourceTree {

  /// 用 `#filePath` 定位自身再向上退三层，这样检查不依赖当前工作目录。
  static let root: String = {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<3 { url.deleteLastPathComponent() }
    return url.path
  }()

  struct Line {
    var path: String
    var number: Int
    var text: String

    var location: String { "\(path):\(number)" }
  }

  /// 剥掉 `//` 行注释和 `/* */` 块注释后的每一行。
  ///
  /// 必须剥：`Ports.swift` 里 `Clock` 的文档注释写着"Core 不许调 `Date()`"，
  /// 不剥注释的话 B3 第一条就假红。那句注释留着，当这条行为的活样本。
  static func lines(under directory: String, excluding excluded: Set<String> = []) -> [Line] {
    var out: [Line] = []
    for path in swiftFiles(under: directory) {
      let name = (path as NSString).lastPathComponent
      guard !excluded.contains(name) else { continue }
      guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { continue }

      let relative = path.replacingOccurrences(of: root + "/", with: "")
      for (index, text) in stripComments(source).split(
        separator: "\n", omittingEmptySubsequences: false
      ).enumerated() {
        out.append(Line(path: relative, number: index + 1, text: String(text)))
      }
    }
    return out
  }

  static func swiftFiles(under directory: String) -> [String] {
    let base = root + "/" + directory
    guard let walker = FileManager.default.enumerator(atPath: base) else { return [] }
    var out: [String] = []
    for case let entry as String in walker where entry.hasSuffix(".swift") {
      out.append(base + "/" + entry)
    }
    return out.sorted()
  }

  static func stripComments(_ source: String) -> String {
    let withoutBlocks = source.replacingOccurrences(
      of: #"/\*[\s\S]*?\*/"#,
      with: "",
      options: .regularExpression
    )
    return
      withoutBlocks
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { $0.replacingOccurrences(of: #"//.*$"#, with: "", options: .regularExpression) }
      .joined(separator: "\n")
  }

  static func matches(_ lines: [Line], pattern: String) -> [Line] {
    lines.filter { $0.text.range(of: pattern, options: .regularExpression) != nil }
  }

  /// 工作树里所有被跟踪意义上的文本文件。不起子进程，所以直接走目录并跳过产物目录。
  static func trackedTextFiles() -> [String] {
    let skipped: Set<String> = [".git", ".build", "dist", ".swiftpm", "DerivedData", ".rail"]
    var out: [String] = []
    guard let walker = FileManager.default.enumerator(atPath: root) else { return [] }
    for case let entry as String in walker {
      let first = entry.split(separator: "/").first.map(String.init) ?? entry
      if skipped.contains(first) {
        walker.skipDescendants()
        continue
      }
      let full = root + "/" + entry
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: full, isDirectory: &isDirectory),
        !isDirectory.boolValue
      else {
        continue
      }
      out.append(entry)
    }
    return out.sorted()
  }
}

// MARK: - B2 · Core 不 import UI

@Test("B2 · DevLauncherCore 不 import SwiftUI / AppKit / Cocoa")
func b2_coreHasNoUIImports() {
  let offenders = SourceTree.matches(
    SourceTree.lines(under: "Sources/DevLauncherCore"),
    pattern: #"^\s*import\s+(SwiftUI|AppKit|Cocoa)\b"#
  )
  #expect(offenders.isEmpty, "Core 里出现了 UI import：\(offenders.map(\.location))")
}

// MARK: - B3 · 副作用符号只许在 Adapters/

/// Core 的一切副作用必须经 Port 出去（decisions.md D3）。界面层也一样：
/// 想要路径、想调 Finder，从 Adapters 要，不自己问系统。
private let sideEffectSymbols =
  #"Process\(|URLSession|FileManager\.default|NSPasteboard|SecItem|NSWorkspace|Date\(\)"#

@Test("B3 · 副作用符号只出现在 DevLauncherApp/Adapters/")
func b3_sideEffectsOnlyInAdapters() {
  let core = SourceTree.matches(
    SourceTree.lines(under: "Sources/DevLauncherCore"), pattern: sideEffectSymbols)
  #expect(core.isEmpty, "Core 里出现了直接副作用：\(core.map(\.location))")

  let appOutsideAdapters =
    SourceTree
    .matches(SourceTree.lines(under: "Sources/DevLauncherApp"), pattern: sideEffectSymbols)
    .filter { !$0.path.contains("/Adapters/") }
  #expect(appOutsideAdapters.isEmpty, "Adapters 之外出现了副作用符号：\(appOutsideAdapters.map(\.location))")
}

@Test("B3 的扫描器会剥注释 —— 否则 Ports.swift 里那句文档注释就是假阳性")
func b3_scannerStripsComments() {
  let stripped = SourceTree.stripComments(
    """
    /// Core 不许调 `Date()`
    let a = 1 // NSWorkspace
    /* NSPasteboard */
    let b = Date()
    """
  )
  #expect(
    SourceTree.matches([.init(path: "x", number: 1, text: stripped)], pattern: sideEffectSymbols)
      .count == 1)
}

// MARK: - B4 · 契约类型只在 Core 声明

@Test("B4 · App 侧不得另外声明一份 Codable 的契约类型")
func b4_noDuplicateContractTypes() {
  let offenders = SourceTree.matches(
    SourceTree.lines(under: "Sources/DevLauncherApp"),
    pattern: #"(struct|enum|class|extension)\s+\w+\s*:\s*[^=\n]*\b(Codable|Decodable|Encodable)\b"#
  )
  #expect(offenders.isEmpty, "App 侧出现了契约类型的第二份声明：\(offenders.map(\.location))")
}

// MARK: - B5 · 内置预设不是手写 JSON

@Test("B5 · Sources/ 下不得有 .json —— 预设只能由 BuiltinRules 用 Core 的类型构造")
func b5_noJSONInSources() {
  let jsonFiles = SourceTree.trackedTextFiles().filter {
    $0.hasPrefix("Sources/") && $0.hasSuffix(".json")
  }
  #expect(jsonFiles.isEmpty, "Sources/ 下出现了 JSON：\(jsonFiles)")
}

// MARK: - B6 · rules.json 的形状不会悄悄漂移

/// `knowledge/stack/contract-boundary` 在本项目的落法：Core 的类型是唯一真相，
/// `rules.json` 是它的下游。改了类型形状就必须同时更新金样本，二者不可能各走各的。
///
/// 更新金样本：`DEVLAUNCHER_UPDATE_GOLDEN=1 swift test`
@Test("B6 · 内置预设编码出来的 JSON 与金样本逐字节相符")
func b6_builtinRulesMatchGolden() throws {
  let goldenPath = SourceTree.root + "/Tests/DevLauncherCoreTests/Fixtures/default-rules.json"
  let encoded = try Store.makeEncoder().encode(BuiltinRules.defaultRuleSet())

  if ProcessInfo.processInfo.environment["DEVLAUNCHER_UPDATE_GOLDEN"] == "1" {
    try encoded.write(to: URL(fileURLWithPath: goldenPath))
    return
  }

  let golden = try #require(
    try? Data(contentsOf: URL(fileURLWithPath: goldenPath)),
    "金样本不存在。跑 DEVLAUNCHER_UPDATE_GOLDEN=1 swift test 生成，然后 review 内容。"
  )
  #expect(
    encoded == golden,
    """
    内置预设的 JSON 与金样本不一致。\(firstDifference(encoded, golden))
    确认是有意的改动后，跑 DEVLAUNCHER_UPDATE_GOLDEN=1 swift test 更新金样本，并 review 生成的 diff。
    """
  )
}

/// 只说"1601 bytes != 1583 bytes"没法用。指出第一处不同的行，才看得出改了什么。
private func firstDifference(_ lhs: Data, _ rhs: Data) -> String {
  let a = String(decoding: lhs, as: UTF8.self).split(
    separator: "\n", omittingEmptySubsequences: false)
  let b = String(decoding: rhs, as: UTF8.self).split(
    separator: "\n", omittingEmptySubsequences: false)

  for index in 0..<max(a.count, b.count)
  where index >= min(a.count, b.count) || a[index] != b[index] {
    let mine = index < a.count ? String(a[index]) : "(没有这一行)"
    let theirs = index < b.count ? String(b[index]) : "(没有这一行)"
    return """

      第 \(index + 1) 行起不同：
        现在生成的：\(mine.trimmingCharacters(in: .whitespaces))
        金样本里的：\(theirs.trimmingCharacters(in: .whitespaces))
      """
  }
  return "（逐行相同，差异在行尾或编码上。）"
}

// MARK: - B7 · 默认测试集不碰真实世界

@Test("B7 · 测试里不起真实子进程、不发网络请求、不碰真实 Keychain 或剪贴板")
func b7_testsDoNotTouchTheRealWorld() {
  let offenders =
    SourceTree
    .matches(
      SourceTree.lines(under: "Tests", excluding: ["IntegrationTests.swift"]),
      pattern: #"Process\(|URLSession|SecItem|NSPasteboard"#
    )
    // BoundaryTests 自己要走源码树，FileManager 是它的工作方式，不在这条禁令里。
    .filter { !$0.path.hasSuffix("BoundaryTests.swift") }
  #expect(offenders.isEmpty, "测试碰到了真实世界：\(offenders.map(\.location))")
}

// MARK: - B8 · 集成测试默认不跑

@Test("B8 · IntegrationTests 里每个 @Test 都带环境变量开关")
func b8_integrationTestsAreGated() throws {
  let path = SourceTree.root + "/Tests/DevLauncherCoreTests/IntegrationTests.swift"
  let source = try String(contentsOfFile: path, encoding: .utf8)
  let stripped = SourceTree.stripComments(source)

  let testAttributes =
    stripped
    .split(separator: "\n", omittingEmptySubsequences: false)
    .filter { $0.range(of: #"^\s*@Test"#, options: .regularExpression) != nil }

  #expect(testAttributes.isEmpty == false, "IntegrationTests.swift 里一个 @Test 都没有")
  for attribute in testAttributes {
    #expect(
      attribute.contains("integrationEnabled"),
      "这个 @Test 没有带开关，默认会跑：\(attribute.trimmingCharacters(in: .whitespaces))"
    )
  }
}

// MARK: - B9 · 凭据不进仓库

/// 形状匹配，不是真 token。写成拼接是为了避免这个模式本身命中自己。
private let credentialShapes = [
  "ghp" + "_[A-Za-z0-9]{20,}",
  "gho" + "_[A-Za-z0-9]{20,}",
  "github" + "_pat_[A-Za-z0-9_]{20,}",
  "lin" + "_api_[A-Za-z0-9]{20,}",
]

@Test("B9 · 工作树里没有 token 形状的字符串")
func b9_noCredentialsInRepository() {
  var offenders: [String] = []
  for relative in SourceTree.trackedTextFiles() {
    guard
      let source = try? String(contentsOfFile: SourceTree.root + "/" + relative, encoding: .utf8)
    else {
      continue
    }
    for shape in credentialShapes where source.range(of: shape, options: .regularExpression) != nil
    {
      offenders.append("\(relative) 命中 \(shape)")
    }
  }
  #expect(offenders.isEmpty, "仓库里出现了 token 形状的字符串：\(offenders)")
}

// MARK: - B10 · .app 是构建产物不是仓库内容

@Test("B10 · .gitignore 挡住 dist/ 与 .build/，且工作树里没有 dist/ 内容")
func b10_buildOutputIsNotInRepository() throws {
  let gitignore = try String(contentsOfFile: SourceTree.root + "/.gitignore", encoding: .utf8)
  #expect(gitignore.contains("dist/"), ".gitignore 没挡 dist/")
  #expect(gitignore.contains(".build/"), ".gitignore 没挡 .build/")

  let leaked = SourceTree.trackedTextFiles().filter { $0.hasPrefix("dist/") }
  #expect(leaked.isEmpty, "dist/ 下的东西进了工作树：\(leaked)")
}

// MARK: - B11 · UI 基础控件只有一份尺寸真相

@Test("B11 · 页面不得绕过 UI Foundation 自行声明 switch 尺寸")
func b11_sharedControlSizing() {
  let offenders =
    SourceTree
    .matches(
      SourceTree.lines(under: "Sources/DevLauncherApp"),
      pattern: #"toggleStyle\(\.switch\)|controlSize\(\.mini\)"#
    )
    .filter { !$0.path.hasSuffix("DesignSystem/UIFoundation.swift") }
  #expect(offenders.isEmpty, "页面绕过了统一开关：\(offenders.map(\.location))")
}

@Test("B12 · 候选浮层不得读取执行计划或技术参数")
func b12_candidatePanelHasNoTechnicalParameters() {
  let offenders = SourceTree.matches(
    SourceTree.lines(under: "Sources/DevLauncherApp/Panel"),
    pattern: #"candidate\.(plan|scriptPath|arguments|interpreter)|urlTemplate|issueURLTemplate"#
  )
  #expect(offenders.isEmpty, "候选浮层读取了技术参数：\(offenders.map(\.location))")

  let panelLines = SourceTree.lines(under: "Sources/DevLauncherApp/Panel")
  #expect(
    panelLines.contains { $0.text.contains("Text(hintText)") },
    "候选浮层缺少合并后的单段文案"
  )
  #expect(
    panelLines.contains { $0.text.contains("candidate.availability.reason ?? candidate.detail") },
    "候选浮层缺少简短提示"
  )
  #expect(
    panelLines.contains { $0.text.contains("Text(candidate.title)") } == false,
    "候选浮层把动作名称拆成了第二段文本"
  )
}
