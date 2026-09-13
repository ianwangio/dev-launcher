# DevLauncherCore

纯逻辑。**不 import SwiftUI / AppKit / Cocoa，不直接制造副作用。**

这条不是风格偏好：没有图形界面时，这是唯一能跑测试的划法。所有副作用
（子进程、网络、文件系统、时钟、剪贴板、Keychain、打开 URL）经 `Ports/` 的七个协议注入，
真实实现全在 `DevLauncherApp/Adapters/`，测试用替身。

违反会被 `Tests/DevLauncherCoreTests/BoundaryTests.swift` 的 B2 / B3 抓住，
`swift test` 直接红，失败信息带文件和行号。

## 三层，依赖只许自上而下

| 层 | 内容 | 允许依赖 |
|---|---|---|
| `Contract/` | `Rule` `Action` `RuleSet` `Settings` `Candidate` | 仅 Foundation |
| `Ports/` | 七个协议 | Contract |
| Domain | `Matching/` `Actions/` `GitHub/` `Storage/` `Presets/` | Contract + Ports |

`Contract/` 是规则 schema 的**唯一真相**。`rules.json` 是它的序列化结果，
界面表单是它的投影，内置预设是用同一套类型构造出来的值。
App 侧另写一份「稍微不一样的」规则结构体会被 B4 抓住；
`Sources/` 下出现手写 JSON 会被 B5 抓住；
改了类型形状而没更新金样本会被 B6 抓住。

## 两个纯函数

`Matcher.match(text:rules:)` 和 `ActionResolver` 的模板展开是纯函数，
表驱动的用例直接写，不需要任何替身。

`Matcher` **不持有任何 Port** —— 它没有能力产生副作用。
「匹配只负责弹出候选，点击之后才执行」这条安全边界是靠这个结构保证的。

## 两处值得知道的实现细节

- `ExecutablePathFilter` 只接受绝对路径、且 basename 相符的行。本机 `gh` 是用户 zsh 里的
  shell function，`$SHELL -ilc 'command -v gh'` 返回的是字面的 `gh` —— 把它当路径缓存下来，
  子进程会起不来，而且错误现象离原因很远。
- `HistoryEntry` 的字段是固定一组，**没有任何一个能容纳剪贴板原文**。
  「剪贴板内容不落盘」靠类型形状保证，不靠调用方自觉。
