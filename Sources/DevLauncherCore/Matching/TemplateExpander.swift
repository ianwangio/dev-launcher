import Foundation

/// 把模板里的 `$0`..`$9` 换成捕获组。
///
/// `$0` 是整段匹配，`$1`..`$9` 是第 1..9 个捕获组。`$$` 是一个字面的 `$`。
/// 引用了不存在的组，原样保留 —— 这样用户在规则编辑器里能看见自己写错了，
/// 而不是得到一个悄悄少了一段的 URL。
public enum TemplateExpander {

  public enum Escaping: Sendable {
    /// 原样代入。用于脚本参数：参数是直接 exec 传进去的，不经 shell，不需要转义。
    case raw
    /// 百分号编码。用于 URL 模板：路径里的 `/`、空格、中文都要编码，
    /// 否则 `claude://code/new?folder=/Users/x/我的 项目` 会拼出一个非法 URL。
    case percentEncoded
  }

  /// URL 里代入值时允许原样保留的字符：RFC 3986 的 unreserved 集合。
  /// 取这么严是刻意的 —— 代入的值是剪贴板来的，宁可多编码也不要让它改变 URL 的结构。
  private static let unreserved = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
  )

  public static func expand(_ template: String, captures: [String], escaping: Escaping) -> String {
    var out = ""
    out.reserveCapacity(template.count)

    var i = template.startIndex
    while i < template.endIndex {
      let ch = template[i]
      guard ch == "$" else {
        out.append(ch)
        i = template.index(after: i)
        continue
      }

      let next = template.index(after: i)
      guard next < template.endIndex else {
        out.append(ch)
        i = next
        continue
      }

      let marker = template[next]
      if marker == "$" {
        out.append("$")
        i = template.index(after: next)
        continue
      }

      guard let digit = marker.wholeNumberValue, (0...9).contains(digit), digit < captures.count
      else {
        // 引用了不存在的组：原样留着。
        out.append(ch)
        i = next
        continue
      }

      out.append(escape(captures[digit], escaping))
      i = template.index(after: next)
    }

    return out
  }

  /// v2 named tokens use `{{name}}`. Legacy `$0...$9` tokens continue to work.
  public static func expand(
    _ template: String,
    captures: [String],
    namedValues: [String: String],
    escaping: Escaping
  ) -> String {
    var expanded = expand(template, captures: captures, escaping: escaping)
    var values = namedValues
    if let whole = captures.first { values["匹配内容"] = whole }
    for (name, value) in values {
      expanded = expanded.replacingOccurrences(of: "{{\(name)}}", with: escape(value, escaping))
    }
    return expanded
  }

  private static func escape(_ value: String, _ escaping: Escaping) -> String {
    switch escaping {
    case .raw:
      return value
    case .percentEncoded:
      return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
  }
}
