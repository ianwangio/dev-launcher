# DevLauncher

macOS 原生应用。常驻后台监听剪贴板，内容匹配上规则时在鼠标附近弹出候选面板，
点击候选项才执行动作 —— 用默认浏览器打开 URL，或用本机解释器跑一个脚本。

公开发布的自用工具：应用包使用临时签名，未获 Developer ID 签名或公证；不做自动更新。

## 直接下载

需要 **macOS 26、Apple Silicon（arm64）**。从 [最新 Release](https://github.com/ianwangio/dev-launcher/releases/latest) 下载 `DevLauncher-v0.1.0-macos-arm64.zip` 和 `SHA256SUMS.txt`。GitHub 页面上的 `Source code (zip)` 只是源码，不能直接运行。

把两个下载文件放在同一目录，先核对下载包：

```bash
shasum -a 256 -c SHA256SUMS.txt
```

解压 ZIP，把 `DevLauncher.app` 移到“应用程序”。此版未公证；确认下载来源和摘要后，在终端**只对这个应用**执行：

```bash
xattr -dr com.apple.quarantine /Applications/DevLauncher.app
open /Applications/DevLauncher.app
```

若把应用放在别的位置，替换命令中的应用路径。此命令不关闭 macOS 的全局安全设置。升级时先退出应用，再用新版本 `.app` 替换旧版本；规则、设置和历史保留在自己的 `~/Library/Application Support/DevLauncher/`。发布者流程见 [Release 文档](docs/release.md)。

## 从源码运行

```bash
swift build            # 编译
swift test             # 单测与架构边界检查的唯一入口
Scripts/build-app.sh   # 先跑测试，再组装 dist/DevLauncher.app
open dist/DevLauncher.app
```

最低系统 macOS 26，需要 Xcode 26 的工具链（Swift 6.3）。没有第三方依赖，
`Package.swift` 的 `dependencies` 是空的。

## 它怎么工作

```
NSPasteboard 轮询（500ms，只比 changeCount）
   ↓ 变了才取内容；空白 / 未变 / 超过 4096 字符 → 丢弃
Matcher            纯函数：文本 + 规则 → 命中结果
   ↓
ActionResolver     展开模板，查 scheme 有没有处理者、解释器在不在、路径存不存在
   ↓ 候选项（可点 / 置灰 + 原因），每项都写着「将要做什么」
NSPanel            鼠标右上方 12pt，不抢焦点，5 秒无操作消失
   ↓ 用户点击 ← 在此之前不打开任何东西、不执行任何脚本
WorkspaceURLOpener 或 ProcessCommandRunner
   ↓
history.json       只记规则 id、动作序号、时间。剪贴板内容不落盘。
```

**匹配只负责弹出候选，点击之后才有副作用。** 剪贴板必然会捎带密码和 token，
所以这条是底线，由 `Matcher` 不持有任何 Port（没有能力产生副作用）从结构上保证，
并由一条测试盯着。

## 规则住在哪

```
~/Library/Application Support/DevLauncher/
  rules.json      规则
  settings.json   轮询间隔、长度上限、面板停留时间、Linear workspace 与 team key
  history.json    打开历史，上限 1000 条
```

首次启动写入三条内置预设。`rules.json` 就是规则的全部 —— 主窗口给了
「在 Finder 中显示」和「重新载入规则」两个按钮，手改完点重新载入即可。

一条规则的形状：

```json
{
  "id": "builtin.local-path",
  "name": "本地路径",
  "enabled": true,
  "pattern": "^(?:/|~/)[^\\s]+$",
  "caseInsensitive": false,
  "requiresExistingPath": true,
  "actions": [
    { "type": "openURL", "title": "Claude Code 终端", "urlTemplate": "claude-cli://open?cwd=$0" }
  ]
}
```

模板里 `$0` 是整段匹配，`$1`..`$9` 是捕获组，`$$` 是字面的 `$`。
URL 模板里代入的值会做百分号编码；脚本参数不编码（它们是直接 exec 传进去的，不经 shell）。

三种动作：

| type | 字段 | 做什么 |
|---|---|---|
| `openURL` | `urlTemplate` | 展开后交给系统默认应用 |
| `runScript` | `scriptPath` `args` | 按 shebang 或扩展名选解释器执行 |
| `repoPicker` | `issueURLTemplate` | 从已刷新仓库列表选择 GitHub repo 并打开对应编号 |

Linear API key 存 Keychain（service `DevLauncher`），不进任何 JSON。

## 目录

```
Sources/DevLauncherCore/   纯逻辑、规则契约、匹配、动作、GitHub 与存储。
Sources/DevLauncherApp/    界面、系统交互与副作用适配器。
Tests/DevLauncherCoreTests/ 单测、BoundaryTests.swift 架构检查和可选的真实 gh 集成测试。
Scripts/build-app.sh      测试、编译并组装本机 .app。
Scripts/package-release.sh 从干净提交制作 Release ZIP 和摘要。
docs/release.md            发布者流程。
```

依赖方向只有 App → Core。反过来写会让 `swift build` 报 target 循环依赖。

## 暂未提供

Developer ID 公证、Intel 构建、自动更新和 AI 动作类型。

## 给 agent 的说明

见 [AGENTS.md](AGENTS.md)。
