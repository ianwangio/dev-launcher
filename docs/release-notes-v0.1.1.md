# DevLauncher v0.1.1

本次更新让 GitHub 仓库候选在应用长时间运行时也能保持新鲜，同时继续优先使用本地缓存，避免联网刷新阻塞界面。

## 更新内容

- 启动时先显示任何可解码的仓库缓存，不等待 GitHub 网络请求。
- 仓库缓存的陈旧阈值从 24 小时延长为 7 天。
- 应用运行期间每 24 小时后台刷新一次“集成”页已勾选仓库的最新 PR 编号。
- 定时刷新只查询已勾选仓库；手动“刷新/重新检测”继续执行全量账号、Organization 和仓库发现。
- 单个仓库刷新失败时保留原缓存，并在界面提示失败项，不丢失其他仓库的成功更新。
- 没有缓存的首次运行仍会在后台完成一次全量发现。

从旧版本升级时，先退出 DevLauncher，再替换 `DevLauncher.app`。原有规则、设置、仓库选择和历史继续保留在 `~/Library/Application Support/DevLauncher/`。

下载 `DevLauncher-v0.1.1-macos-arm64.zip`，解压后得到 `DevLauncher.app`。需要 macOS 26 和 Apple Silicon；此包不支持 Intel Mac。

应用使用临时签名，**未获 Developer ID 签名或 Apple 公证**。先核对 ZIP 摘要，确认包来自 `ianwangio/dev-launcher`，再把应用移到“应用程序”。macOS 首次启动若拦截下载的应用，请自行在终端只对它执行：

```bash
xattr -dr com.apple.quarantine /Applications/DevLauncher.app
open /Applications/DevLauncher.app
```

若安装在其他位置，只替换上面命令中的应用路径。该命令只移除 `DevLauncher.app` 的下载隔离属性，不会关闭全局 Gatekeeper 或 SIP。应用不会自动更新。

ZIP 的 SHA-256 值会在正式打包时附在说明末尾，并作为 `SHA256SUMS.txt` 提供。把 ZIP 和摘要文件放在同一目录，可运行：

```bash
shasum -a 256 -c SHA256SUMS.txt
```

GitHub 自动附带的 `Source code (zip)` 是源码快照，不是可运行的应用包。
