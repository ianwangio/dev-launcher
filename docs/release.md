# DevLauncher 发布者流程

本仓库通过本机 macOS 26 / Apple Silicon 工具链组装应用，再把 ZIP 作为独立步骤上传到公开 GitHub Release。`swift test` 是唯一测试入口，`Scripts/build-app.sh` 和 `Scripts/package-release.sh` 都会先经过它。

以下示例默认准备 `v0.1.1`。后续版本只需替换 `RELEASE_TAG`；标签、应用 Info.plist、包名和 Release 说明必须使用同一个版本。

```bash
RELEASE_TAG="${RELEASE_TAG:-v0.1.1}"
RELEASE_VERSION="${RELEASE_TAG#v}"
```

## 1. 提交并审查源码

先更新版本化 Release 说明和本手册，再更新 `Scripts/build-app.sh` 的 `VERSION`。审查所有将公开的非忽略文件及本机路径；`.rail/` 是被 `.gitignore` 忽略的本地流程状态，不应加入提交。也不要把 Keychain 凭据、API token 或构建出的 `dist/` 加入仓库。

```bash
swift test
git status --short
git add <本次明确审查过的文件>
git diff --cached --stat
git diff --cached --check
git commit -m "release: prepare DevLauncher $RELEASE_TAG"
```

提交后记下 `git rev-parse HEAD`。所有发布文档、脚本和本次功能改动必须在这个提交里；本机 `.rail/` 状态保留但不进入 Git。打包从**该提交的干净隔离 checkout** 运行，不复制本机流程状态。提交和 Release 不替其他 `rail` 功能流程签名。

## 2. 从干净提交打包

在仓库根目录用 `mktemp` 创建隔离 worktree，运行打包脚本，然后把三个产物复制回原仓库被忽略的 `dist/`：

```bash
RELEASE_REPO_ROOT="$PWD"
RELEASE_BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/devlauncher-$RELEASE_TAG.XXXXXX")"
git worktree add --detach "$RELEASE_BUILD_ROOT/source" HEAD
(
  cd "$RELEASE_BUILD_ROOT/source"
  Scripts/package-release.sh "$RELEASE_TAG"
)
mkdir -p "$RELEASE_REPO_ROOT/dist"
cp "$RELEASE_BUILD_ROOT/source/dist/DevLauncher-$RELEASE_TAG-macos-arm64.zip" "$RELEASE_REPO_ROOT/dist/"
cp "$RELEASE_BUILD_ROOT/source/dist/SHA256SUMS.txt" "$RELEASE_REPO_ROOT/dist/"
cp "$RELEASE_BUILD_ROOT/source/dist/release-notes-$RELEASE_TAG.md" "$RELEASE_REPO_ROOT/dist/"
git worktree remove "$RELEASE_BUILD_ROOT/source"
rmdir "$RELEASE_BUILD_ROOT"
(
  cd "$RELEASE_REPO_ROOT/dist"
  shasum -a 256 -c SHA256SUMS.txt
)
```

脚本拒绝错误标签、肮脏工作树、版本或架构不符，并在 ZIP 解压后复查签名。最终应得到 `dist/DevLauncher-$RELEASE_TAG-macos-arm64.zip`、`dist/SHA256SUMS.txt` 和 `dist/release-notes-$RELEASE_TAG.md`。

## 3. 创建标签并推送

只有第 2 步全部通过后才创建标签。确保远端精确为 `https://github.com/ianwangio/dev-launcher.git`，`gh auth status` 显示 `ianwangio` 可用，远端同名标签不存在且远端 `main` 没有新提交。

```bash
git remote get-url origin
git fetch origin main --tags
git ls-remote --tags origin "refs/tags/$RELEASE_TAG"
git tag -a "$RELEASE_TAG" -m "DevLauncher $RELEASE_TAG"
GH_TOKEN="$(gh auth token --user ianwangio)" git -c credential.helper= \
  -c 'credential.helper=!gh auth git-credential' \
  push --atomic origin main "refs/tags/$RELEASE_TAG"
```

单次推送只在该命令中覆盖 Git 凭据助手，不把 token 写入远端 URL，也不改变全局 Git 配置。若同名标签已经存在，先核对 `git rev-list -n 1 "$RELEASE_TAG"`，不要重写已发布标签。推送后必须核对 GitHub 上 `main` 与解引用后的标签都指向打包提交。

## 4. 创建公开 Release

创建或修改 GitHub Release 是独立的外部发布动作。若本轮只获准构建并推送源码/标签，在第 3 步停止，不执行本节。

获得明确授权后，确认 `dist/` 中仍是第 2 步制作且重验过的三个文件，再执行：

```bash
GH_TOKEN="$(gh auth token --user ianwangio)" gh release create "$RELEASE_TAG" \
  "dist/DevLauncher-$RELEASE_TAG-macos-arm64.zip" dist/SHA256SUMS.txt \
  --repo ianwangio/dev-launcher --verify-tag \
  --title "DevLauncher $RELEASE_TAG" \
  --notes-file "dist/release-notes-$RELEASE_TAG.md"
```

Release 说明应提示下载者只对 `DevLauncher.app` 运行 Gatekeeper 下载隔离命令，并列出 ZIP 的 SHA-256。当前包仅有临时签名，不能标成 Apple 已公证。

## 5. 独立下载复验

不要用本机 `dist/` 代替远端资产验收。Release 创建后，从 GitHub 实际下载到新的临时目录：

```bash
RELEASE_DOWNLOAD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/devlauncher-download-$RELEASE_TAG.XXXXXX")"
gh release download "$RELEASE_TAG" --repo ianwangio/dev-launcher \
  --dir "$RELEASE_DOWNLOAD_ROOT"
cd "$RELEASE_DOWNLOAD_ROOT"
shasum -a 256 -c SHA256SUMS.txt
ditto -x -k "DevLauncher-$RELEASE_TAG-macos-arm64.zip" .
plutil -extract CFBundleShortVersionString raw DevLauncher.app/Contents/Info.plist
file DevLauncher.app/Contents/MacOS/DevLauncher
codesign --verify --deep --strict DevLauncher.app
```

确认版本为 `$RELEASE_VERSION`、可执行文件为 arm64 后，可在已核对摘要的下载拷贝上执行 `xattr -dr com.apple.quarantine DevLauncher.app` 并真实启动。用 `gh release view "$RELEASE_TAG" --web` 打开最终页面。

## 参考

- [AltTab](https://github.com/lwouis/alt-tab-macos/releases) 把可直接安装的 macOS ZIP 放在 Release 资产里，而非让用户下载源码 ZIP。
- [Architect](https://github.com/forketyfork/architect) 对临时签名、未公证的 macOS 包给出单应用 `xattr -dr com.apple.quarantine` 首次运行命令。
- [ContainerUI](https://github.com/kylemclaren/container-ui) 展示了 macOS 26 应用的版本标签、Release 资产、摘要和 Gatekeeper 说明。
- [GitHub CLI 发布命令](https://cli.github.com/manual/gh_release_create) 与 [Apple 的首次运行说明](https://support.apple.com/en-gb/102445) 用于核对发布语法和安全提示。

公开 `main` 与版本标签不跟踪 `.rail/`。旧克隆若仍含清理前的提交或标签，应重新克隆或以新远端引用同步；不要把旧引用重新推回公开仓库。
