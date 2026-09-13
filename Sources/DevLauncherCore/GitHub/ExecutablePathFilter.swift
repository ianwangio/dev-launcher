import Foundation

/// 从登录 shell 的 `command -v <name>` 输出里挑出真正的可执行文件路径。
///
/// 为什么需要这个：本机实测（shape.md 2.1）`gh` 是用户 zsh 里的一个 shell function，
/// `$SHELL -ilc 'command -v gh'` 返回的是字面的 `gh`，不是路径。rc 文件还会往
/// stdout 混进各种噪音。把这种输出直接当路径缓存下来，子进程就会起不来，
/// 而且错误现象离原因很远。
///
/// 规则只有两条，都很保守：**必须是绝对路径**，**basename 必须就是要找的名字**。
public enum ExecutablePathFilter {

    public static func absolutePath(named name: String, inShellOutput output: String) -> String? {
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("/") else { continue }
            guard !line.contains(" ") else { continue }

            let basename = line.split(separator: "/").last.map(String.init)
            guard basename == name else { continue }

            return line
        }
        return nil
    }
}
