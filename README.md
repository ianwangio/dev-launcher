# DevLauncher

macOS 原生应用。常驻后台监听剪贴板，内容匹配上规则时在鼠标附近弹出候选面板，
点击候选项才执行动作 —— 用默认浏览器打开 URL，或用本机解释器跑一个脚本。

自用工具：不签名、不公证、不上架、不做自动更新，只在本机跑。

## 跑起来

```bash
swift build            # 编译
swift test             # 38 个测试，含 9 条边界检查
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
| `repoPicker` | `issueURLTemplate` | 列出 GitHub repo 供选择（尚未接入，见下） |

Linear API key 存 Keychain（service `DevLauncher`），不进任何 JSON。

## 目录

```
Sources/DevLauncherCore/   纯逻辑。不 import SwiftUI / AppKit，副作用全部经 Port 注入。
  Contract/   Rule Action RuleSet Settings Candidate —— 规则 schema 的唯一真相
  Ports/      七个协议：CommandRunner HTTPClient FileSystem Clock SecretStore URLOpener PasteboardSource
  Matching/   Matcher TemplateExpander ClipboardGate
  Actions/    ActionResolver InterpreterResolver
  GitHub/     ExecutablePathFilter GhPathResolver
  Storage/    Store History
  Presets/    BuiltinRules
Sources/DevLauncherApp/    界面与系统交互。
  Adapters/   七个 Port 的真实实现 + SystemPaths / FinderRevealer
  Panel/      PanelController（NSPanel）PanelView
  Main/       AppModel MainWindowView
Tests/DevLauncherCoreTests/
  CoreTests.swift       27 个单测
  BoundaryTests.swift   B2–B10 边界检查
  IntegrationTests.swift 真实调用本机 gh，默认跳过
  Fixtures/             B6 金样本
```

依赖方向只有 App → Core。反过来写会让 `swift build` 报 target 循环依赖。

## 本期没做的

- **GitHub `#N` 选 repo**：`repoPicker` 动作类型在 schema 里是完整的，面板上也会出现，
  但置灰并写明原因 —— 取 repo 列表（`gh`）和按编号邻近度排序还没接。
- **规则的图形化编辑**：改 `rules.json` 再点「重新载入规则」。
- **AI 动作类型**：本期明确不做，是将来的一种动作类型。

## 给 agent 的说明

见 [AGENTS.md](AGENTS.md)。
