# AGENTS.md

Canonical instructions for agents working in this repository.

## rail
<!-- rail:agents-entry rev=sha256:d0aad6ae3f6d vars= -->

This repository's work runs through `rail`. Invoke the `rail` skill —
installed at `.agents/skills/` and `.claude/skills/`, same content either
way — before any requirement, design, build or change — bug fixes included —
rather than working straight from a request.

Nothing under `.rail/` is edited by hand; every state change goes through a
command.

`.rail/` is local workflow state and is ignored by Git. Keep it in the current
checkout; do not copy it into public commits. In a new checkout, install and
initialize `rail` locally before running a flow.

## 这个仓库

macOS 原生应用，Swift + SwiftPM，无第三方依赖。上手看 [README.md](README.md)。

### 门在哪

```bash
swift test
```

这是唯一入口。它同时跑三样东西：

- Core 的单测；
- `BoundaryTests.swift` 里的 B2–B10 —— 架构边界的机械检查，越界即红，失败信息带文件和行号；
- `Scripts/build-app.sh` 打包前也先跑它，不过就不产出 `.app`。

本仓库通过公开 GitHub Release 分发应用，目前没有 CI。检查不能散成一堆要人记得跑的脚本，只能有 `swift test` 这一个入口；`Scripts/package-release.sh` 通过 `build-app.sh` 调用它。

### 改代码前要知道的三条

1. **`DevLauncherCore` 不许 import SwiftUI / AppKit，也不许直接调
   `Process(` / `URLSession` / `FileManager.default` / `NSPasteboard` / `SecItem` /
   `NSWorkspace` / `Date()`。** 需要副作用就加一个 Port，实现放
   `DevLauncherApp/Adapters/`。B2 / B3 守这条。
2. **规则 schema 的唯一真相是 `Sources/DevLauncherCore/Contract/` 里的类型。**
   `rules.json`、界面表单、内置预设都是它的下游。改了类型形状，
   `DEVLAUNCHER_UPDATE_GOLDEN=1 swift test` 更新 B6 金样本，并 review 生成的 diff。
3. **匹配阶段不许有副作用。** `Matcher` 不持有任何 Port，`ActionResolver` 只做存在性查询。
   要执行的东西一律放到用户点击之后。有一条测试盯着这件事。

### 集成测试

```bash
DEVLAUNCHER_INTEGRATION=1 swift test
```

会真实调用本机 `gh`。默认跳过，断网或没装 gh 时不会红。
