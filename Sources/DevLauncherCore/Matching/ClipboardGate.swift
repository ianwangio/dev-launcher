import Foundation

/// 剪贴板内容进不进正则的前置判断（decisions.md D4）。
///
/// 单独拎出来是因为它是"轻量"这个要求的实际落点，也是唯一一处需要断言
/// "这段内容根本没被处理过"的地方。纯函数，便于直接测。
public enum ClipboardGate {

    public enum Verdict: Equatable, Sendable {
        case process(String)
        case skipEmpty
        case skipTooLong(length: Int, limit: Int)
        case skipUnchanged
    }

    public static func evaluate(text: String?, previous: String?, maxLength: Int) -> Verdict {
        guard let text else { return .skipEmpty }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .skipEmpty }
        guard trimmed != previous else { return .skipUnchanged }
        guard trimmed.count <= maxLength else {
            return .skipTooLong(length: trimmed.count, limit: maxLength)
        }
        return .process(trimmed)
    }
}
