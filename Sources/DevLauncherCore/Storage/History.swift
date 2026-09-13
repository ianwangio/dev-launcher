import Foundation

/// 一次"用户点了某个候选项"的记录。
///
/// 字段是固定的一组，**没有任何一个能容纳剪贴板原文** —— decisions.md D11 那条
/// "剪贴板内容不落盘"是靠这个类型的形状保证的，由 3.4 那条针对性测试守。
public struct HistoryEntry: Codable, Equatable, Sendable {
    public var ruleID: String
    public var actionIndex: Int
    /// 被打开的 repo 全名（`owner/name`）。只有 repoPicker 动作会填，用于 D10 的排序。
    public var repo: String?
    /// issue / PR 编号，同样只服务排序。
    public var number: Int?
    public var openedAt: Date

    public init(ruleID: String, actionIndex: Int, repo: String? = nil, number: Int? = nil, openedAt: Date) {
        self.ruleID = ruleID
        self.actionIndex = actionIndex
        self.repo = repo
        self.number = number
        self.openedAt = openedAt
    }
}

public struct History: Codable, Equatable, Sendable {
    /// 上限 1000 条（decisions.md D5）。超出时丢最旧的。
    public static let capacity = 1000

    public var entries: [HistoryEntry]

    public init(entries: [HistoryEntry]) {
        self.entries = entries
    }

    public mutating func append(_ entry: HistoryEntry) {
        entries.append(entry)
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }
}
