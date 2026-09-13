import Darwin
import DevLauncherCore
import Foundation

/// 用 `posix_spawn` 直接 exec 目标可执行文件。
///
/// 三处都是 decisions.md D9 记下来的前作教训，每一条都被独立审查抓到过：
///
/// 1. **不拼 shell 字符串**。参数走 argv 数组，剪贴板内容永远不会被 shell 解释。
/// 2. **`POSIX_SPAWN_SETSID`，超时杀整个进程组**。交互式 zsh 会忽略 SIGTERM，
///    孙进程会占住管道让读取端永远等不到 EOF。新建 session 之后 `kill(-pid)`
///    能把整棵树带走。
/// 3. **stdin 接 `/dev/null`**。否则子进程可能停在等输入上，表现成"卡住"。
final class ProcessCommandRunner: CommandRunner {

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String]?,
        timeoutSeconds: Double
    ) throws -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw CommandError.notExecutable(executable)
        }

        var outPipe: [Int32] = [-1, -1]
        var errPipe: [Int32] = [-1, -1]
        guard pipe(&outPipe) == 0, pipe(&errPipe) == 0 else {
            throw CommandError.launchFailed("pipe() 失败: errno \(errno)")
        }

        let devNull = open("/dev/null", O_RDONLY)
        guard devNull >= 0 else {
            [outPipe[0], outPipe[1], errPipe[0], errPipe[1]].forEach { close($0) }
            throw CommandError.launchFailed("打不开 /dev/null: errno \(errno)")
        }

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, devNull, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, outPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, errPipe[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, outPipe[0])
        posix_spawn_file_actions_addclose(&fileActions, errPipe[0])

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))

        let argv = [executable] + arguments
        var cArgv: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        cArgv.append(nil)

        var env = ProcessInfo.processInfo.environment
        environment?.forEach { env[$0.key] = $0.value }
        var cEnv: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") }
        cEnv.append(nil)

        var pid: pid_t = 0
        let spawnResult = posix_spawn(&pid, executable, &fileActions, &attributes, cArgv, cEnv)

        posix_spawn_file_actions_destroy(&fileActions)
        posix_spawnattr_destroy(&attributes)
        cArgv.forEach { if let p = $0 { free(p) } }
        cEnv.forEach { if let p = $0 { free(p) } }
        close(devNull)
        close(outPipe[1])
        close(errPipe[1])

        guard spawnResult == 0 else {
            close(outPipe[0])
            close(errPipe[0])
            throw CommandError.launchFailed("posix_spawn 返回 \(spawnResult)")
        }

        // 两个管道各起一个后台读取。不读就可能把子进程写满管道卡死。
        let group = DispatchGroup()
        let collected = OutputBox()
        for (fd, isStdout) in [(outPipe[0], true), (errPipe[0], false)] {
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                let data = Self.drain(fd: fd)
                collected.store(data, isStdout: isStdout)
            }
        }

        let status = Self.wait(pid: pid, timeoutSeconds: timeoutSeconds)
        group.wait()

        guard let exitCode = status else {
            throw CommandError.timedOut(after: timeoutSeconds)
        }

        let (out, err) = collected.take()
        return CommandResult(
            stdout: String(decoding: out, as: UTF8.self),
            stderr: String(decoding: err, as: UTF8.self),
            exitCode: exitCode
        )
    }

    /// 等子进程结束。超时就 `kill(-pid)` 杀掉整个 session，再收尸避免僵尸进程。
    private static func wait(pid: pid_t, timeoutSeconds: Double) -> Int32? {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var status: Int32 = 0

        while true {
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid {
                if status & 0x7F == 0 { return (status >> 8) & 0xFF }
                return -(status & 0x7F)
            }
            if result < 0 { return nil }

            if Date() >= deadline {
                kill(-pid, SIGKILL)
                var discard: Int32 = 0
                waitpid(pid, &discard, 0)
                return nil
            }
            usleep(20_000)
        }
    }

    private static func drain(fd: Int32) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                data.append(contentsOf: buffer[0..<n])
            } else if n == 0 {
                break
            } else if errno == EINTR {
                continue
            } else {
                break
            }
        }
        close(fd)
        return data
    }

    private final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stdout = Data()
        private var stderr = Data()

        func store(_ data: Data, isStdout: Bool) {
            lock.lock()
            defer { lock.unlock() }
            if isStdout { stdout = data } else { stderr = data }
        }

        func take() -> (Data, Data) {
            lock.lock()
            defer { lock.unlock() }
            return (stdout, stderr)
        }
    }
}
