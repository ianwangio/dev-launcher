# DevLauncher v0.1.0

首个公开的 macOS 应用包。下载 `DevLauncher-v0.1.0-macos-arm64.zip`，解压后得到 `DevLauncher.app`。需要 macOS 26 和 Apple Silicon；此包不支持 Intel Mac。

应用使用临时签名，**未获 Developer ID 签名或 Apple 公证**。先核对本 Release 的 ZIP 摘要，确认包来自 `ianwangio/dev-launcher`，再把应用移到“应用程序”。macOS 首次启动若拦截下载的应用，请自行在终端只对它执行：

```bash
xattr -dr com.apple.quarantine /Applications/DevLauncher.app
open /Applications/DevLauncher.app
```

若安装在其他位置，只替换上面命令中的应用路径。该命令只移除 `DevLauncher.app` 的下载隔离属性，不会关闭全局 Gatekeeper 或 SIP。应用不会自动更新；升级时退出旧版本并替换 `.app`，本机规则、设置与历史仍留在 `~/Library/Application Support/DevLauncher/`。

ZIP 的 SHA-256 值会在正式打包时附在本 Release 说明末尾，并作为 `SHA256SUMS.txt` 资产提供。把 ZIP 和摘要文件放在同一目录，可运行：

```bash
shasum -a 256 -c SHA256SUMS.txt
```

GitHub 自动附带的 `Source code (zip)` 是源码快照，不是可运行的应用包。
