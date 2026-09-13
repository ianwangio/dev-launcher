# DevLauncherApp

界面与系统交互。可执行 target，依赖 `DevLauncherCore`。

## Adapters/ 是副作用的唯一出口

`Process(` / `URLSession` / `FileManager.default` / `NSPasteboard` / `SecItem` /
`NSWorkspace` / `Date()` 这些符号**只许出现在 `Adapters/` 里**，由 B3 守。
界面层想要一个路径、想调 Finder，从 Adapters 要，不自己问系统。

（这条在开发时破过一次：`AppModel` 直接调了 `FileManager.default.urls(...)`
和 `NSWorkspace.shared.selectFile(...)`，移进了 `SystemPaths` 与 `FinderRevealer`。）

## ProcessCommandRunner 的三条

都是前作被独立审查抓出来的现象，每条都对应一个具体故障：

1. **参数走 argv 数组，不拼 shell 字符串。** 剪贴板内容会流进这里。
2. **`POSIX_SPAWN_SETSID`，超时 `kill(-pid, SIGKILL)` 杀整个 session。**
   交互式 zsh 会忽略 SIGTERM；孙进程会占住管道让读取端永远等不到 EOF。
3. **stdin 接 `/dev/null`。** 否则子进程可能停在等输入上，表现成「卡住」。

两个管道各起一个后台读取 —— 不读的话子进程写满管道就会卡死。

## PanelController

`NSPanel(.nonactivatingPanel + .borderless)`，`level = .floating`，
`hidesOnDeactivate = false`。**不抢焦点是第一要求**：面板显示时不激活本应用，
用户正在打字的那个窗口不会失去焦点。这也是整个项目里唯一必须用 AppKit 的理由 ——
SwiftUI 做不出非激活浮层。

定位：`NSEvent.mouseLocation` 右上方 12pt，贴屏幕边时翻到另一侧。
`frame(forSize:near:)` 是静态纯函数。

**Esc 只在面板拿到键盘焦点时有效。** global key monitor 需要「输入监听」权限，
而本项目明确不申请那个权限（那等于键盘记录器）。所以用 local monitor。
没点过面板时的关闭途径：5 秒自动消失、点别处、或剪贴板内容再次变化。

## AppModel

把 Core 和 adapter 接起来，持有运行时状态。

- 每 500ms 一次 tick，绝大多数只是一次 `changeCount` 整数比较就结束 ——
  这就是「剪贴板监听要轻量」的全部实现。
- 启动时在后台线程预热解释器路径缓存：解析一次要起一次登录 shell，可能到秒级，
  放在面板渲染时做会卡住界面。
- 主窗口有个「手工触发」框：输入文本直接走同一条 `Matcher → ActionResolver → 面板` 链路，
  不用真的复制。给实机验证用的，真实剪贴板路径进的是同一个 `showPanel`。

## URLSessionHTTPClient 现在没有调用方

这是有意的，不是死代码。Linear 的主路径不调 API（构造 URL 交给浏览器就行），
但 `HTTPClient` 这个 Port 要有实现才能构造 Core 的对象。
真正接 Linear API 拉 team key 列表时替换它。
