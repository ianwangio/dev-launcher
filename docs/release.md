# DevLauncher 发布者流程

本仓库通过本机 macOS 26 / Apple Silicon 工具链组装应用，再把 ZIP 上传为公开 GitHub Release 资产。`swift test` 是唯一测试入口，`Scripts/build-app.sh` 和 `Scripts/package-release.sh` 都会先经过它。首版标签为 `v0.1.0`，与应用 `Info.plist` 里的 `0.1.0` 对齐。

## 1. 提交并审查源码

先审查所有将公开的非忽略文件，包括 `.rail` 开发记录与本机路径；不要把 Keychain 凭据、API token 或构建出的 `dist/` 加入仓库。运行：

```bash
swift test
git status --short
git add -A
git diff --cached --stat
git diff --cached --check
git commit -m "release: prepare DevLauncher v0.1.0"
```

提交后记下 `git rev-parse HEAD`。所有发布文档、脚本和用户要求的其他当前改动必须在这个提交里。若 agent 正在用 `rail` 记录执行状态，`.rail/rail.db` 可能在提交后再次变化；打包请从**该提交的干净隔离 checkout** 运行，不要让后续流程事件混入构建。提交与 Release 不替其他 `rail` 功能流程签名。

## 2. 从干净提交打包

在仓库根目录创建隔离 checkout；完成后可用 `git worktree remove` 清理。下列示例采用固定目录，请先确认它不存在：

```bash
git worktree add --detach /tmp/dev-launcher-v0.1.0-build HEAD
cd /tmp/dev-launcher-v0.1.0-build
Scripts/package-release.sh v0.1.0
```

脚本输出 `dist/DevLauncher-v0.1.0-macos-arm64.zip`、`dist/SHA256SUMS.txt` 和 `dist/release-notes-v0.1.0.md`。它拒绝错误标签、肮脏工作树、版本或架构不符，并在 ZIP 解压后复查签名。把这三个文件复制到原仓库的 `dist/`；复制后再次运行 `shasum -a 256 -c SHA256SUMS.txt`。`dist/` 已被 `.gitignore` 忽略，不进入源码提交。

## 3. 创建公开仓库并推送

确保 `gh auth status` 显示 `ianwangio` 可用。当前仓库尚无远端时，在原仓库根目录执行：

```bash
GH_TOKEN="$(gh auth token --user ianwangio)" gh repo create ianwangio/dev-launcher --public --source=. --remote=origin
git push -u origin main
git tag -a v0.1.0 -m "DevLauncher v0.1.0"
git push origin v0.1.0
```

若公开仓库已存在，跳过创建，先检查 `git remote -v` 是否精确指向 `https://github.com/ianwangio/dev-launcher.git`。若标签已存在，先检查 `git rev-list -n 1 v0.1.0` 与打包提交一致，不重写已发布标签。发布者必须核对 GitHub 上 `main` 和 `v0.1.0` 都指向预期源码；不要把之后仅记录 `rail` 事件的提交误当应用源码。

## 4. 创建 Release

仍在原仓库根目录，确认 `dist/` 中是第 2 步制作且重验过的三个文件，然后执行：

```bash
GH_TOKEN="$(gh auth token --user ianwangio)" gh release create v0.1.0 \
  dist/DevLauncher-v0.1.0-macos-arm64.zip dist/SHA256SUMS.txt \
  --repo ianwangio/dev-launcher --verify-tag \
  --title "DevLauncher v0.1.0" \
  --notes-file dist/release-notes-v0.1.0.md
```

Release 说明中会直接提示下载者自行运行只针对 `DevLauncher.app` 的 Gatekeeper 下载隔离命令，并列出 ZIP 的 SHA-256。此版仅有临时签名，不能标成 Apple 已公证。

## 5. 独立下载复验

不要用本机 `dist/` 代替远端资产验收。新建空目录，从 GitHub 实际下载：

```bash
mkdir -p /tmp/dev-launcher-v0.1.0-download
gh release download v0.1.0 --repo ianwangio/dev-launcher \
  --dir /tmp/dev-launcher-v0.1.0-download
cd /tmp/dev-launcher-v0.1.0-download
shasum -a 256 -c SHA256SUMS.txt
ditto -x -k DevLauncher-v0.1.0-macos-arm64.zip .
plutil -extract CFBundleShortVersionString raw DevLauncher.app/Contents/Info.plist
file DevLauncher.app/Contents/MacOS/DevLauncher
codesign --verify --deep --strict DevLauncher.app
```

确认版本为 `0.1.0`、可执行文件为 arm64 后，可在已核对摘要的下载拷贝上执行 `xattr -dr com.apple.quarantine DevLauncher.app`，再用 `open DevLauncher.app` 验证首次启动。Release 页面和 ZIP 直接下载入口分别是 [Releases](https://github.com/ianwangio/dev-launcher/releases/tag/v0.1.0) 与 [最新资产](https://github.com/ianwangio/dev-launcher/releases/latest/download/DevLauncher-v0.1.0-macos-arm64.zip)。

## 参考

- [AltTab](https://github.com/lwouis/alt-tab-macos/releases) 把可直接安装的 macOS ZIP 放在 Release 资产里，而非让用户下载源码 ZIP。
- [Architect](https://github.com/forketyfork/architect) 对临时签名、未公证的 macOS 包给出单应用 `xattr -dr com.apple.quarantine` 首次运行命令。
- [ContainerUI](https://github.com/kylemclaren/container-ui) 展示了 macOS 26 应用的版本标签、Release 资产、摘要和 Gatekeeper 说明；本仓库首版采用本机脚本与手动 `gh` 发布。
- [GitHub CLI 发布命令](https://cli.github.com/manual/gh_release_create) 与 [Apple 的首次运行说明](https://support.apple.com/en-gb/102445) 用于核对发布语法和安全提示。
