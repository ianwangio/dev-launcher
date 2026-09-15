#!/bin/bash
# 从干净的已提交源码组装可下载的 macOS Release ZIP。
set -euo pipefail

RELEASE_TAG="${1:-}"
if [[ ! "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "用法：Scripts/package-release.sh v0.1.0" >&2
  exit 2
fi

cd "$(dirname "$0")/.."
RELEASE_REPO_ROOT="$PWD"
RELEASE_VERSION="${RELEASE_TAG#v}"
BUILD_VERSION="$(sed -n 's/^VERSION="\([^"]*\)"/\1/p' Scripts/build-app.sh)"
if [[ "$BUILD_VERSION" != "$RELEASE_VERSION" ]]; then
  echo "标签 $RELEASE_TAG 与 build-app.sh 的版本 $BUILD_VERSION 不一致" >&2
  exit 1
fi

git rev-parse --is-inside-work-tree >/dev/null
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo "工作树有未提交文件；请从干净提交或隔离 worktree 打包" >&2
  exit 1
fi
RELEASE_COMMIT="$(git rev-parse HEAD)"

"$RELEASE_REPO_ROOT/Scripts/build-app.sh"

RELEASE_DIST="$RELEASE_REPO_ROOT/dist"
RELEASE_APP="$RELEASE_DIST/DevLauncher.app"
RELEASE_EXEC="$RELEASE_APP/Contents/MacOS/DevLauncher"
RELEASE_PLIST="$RELEASE_APP/Contents/Info.plist"
RELEASE_ZIP_NAME="DevLauncher-$RELEASE_TAG-macos-arm64.zip"
RELEASE_ZIP="$RELEASE_DIST/$RELEASE_ZIP_NAME"
RELEASE_SUMS="$RELEASE_DIST/SHA256SUMS.txt"
RELEASE_NOTES="$RELEASE_DIST/release-notes-$RELEASE_TAG.md"
RELEASE_NOTES_SOURCE="$RELEASE_REPO_ROOT/docs/release-notes-$RELEASE_TAG.md"

[[ -f "$RELEASE_NOTES_SOURCE" ]] || { echo "缺少 Release 说明：$RELEASE_NOTES_SOURCE" >&2; exit 1; }
[[ -x "$RELEASE_EXEC" ]] || { echo "缺少应用可执行文件：$RELEASE_EXEC" >&2; exit 1; }

check_app() {
  local app_path="$1"
  local plist_path="$app_path/Contents/Info.plist"
  local exec_path="$app_path/Contents/MacOS/DevLauncher"
  local app_version app_build min_system app_archs

  app_version="$(plutil -extract CFBundleShortVersionString raw "$plist_path")"
  app_build="$(plutil -extract CFBundleVersion raw "$plist_path")"
  min_system="$(plutil -extract LSMinimumSystemVersion raw "$plist_path")"
  app_archs="$(lipo -archs "$exec_path")"
  [[ "$app_version" == "$RELEASE_VERSION" && "$app_build" == "$RELEASE_VERSION" ]] || {
    echo "应用版本与 $RELEASE_TAG 不符：$app_version / $app_build" >&2
    return 1
  }
  [[ "$min_system" == "26.0" ]] || { echo "最低系统版本不是 macOS 26：$min_system" >&2; return 1; }
  [[ "$app_archs" == "arm64" ]] || { echo "应用不是单一 arm64：$app_archs" >&2; return 1; }
  codesign --verify --deep --strict "$app_path"
}

check_app "$RELEASE_APP"
rm -f "$RELEASE_ZIP" "$RELEASE_SUMS" "$RELEASE_NOTES"
ditto -c -k --sequesterRsrc --keepParent "$RELEASE_APP" "$RELEASE_ZIP"

RELEASE_VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devlauncher-package.XXXXXX")"
trap 'rm -rf "$RELEASE_VERIFY_DIR"' EXIT
ditto -x -k "$RELEASE_ZIP" "$RELEASE_VERIFY_DIR"
check_app "$RELEASE_VERIFY_DIR/DevLauncher.app"

(
  cd "$RELEASE_DIST"
  shasum -a 256 "$RELEASE_ZIP_NAME" > SHA256SUMS.txt
  shasum -a 256 -c SHA256SUMS.txt
)
RELEASE_SHA256="$(awk '{print $1}' "$RELEASE_SUMS")"

cat "$RELEASE_NOTES_SOURCE" > "$RELEASE_NOTES"
cat >> "$RELEASE_NOTES" <<NOTES

## 发布资产校验

源码提交：\`$RELEASE_COMMIT\`

\`$RELEASE_ZIP_NAME\` 的 SHA-256：\`$RELEASE_SHA256\`

同名摘要也在 \`SHA256SUMS.txt\` 中。下载 ZIP 和摘要文件后，将它们放在同一目录运行 \`shasum -a 256 -c SHA256SUMS.txt\`。
NOTES

echo "Release 源码：$RELEASE_COMMIT"
echo "应用 ZIP：$RELEASE_ZIP"
echo "SHA-256：$RELEASE_SHA256"
echo "摘要文件：$RELEASE_SUMS"
echo "发布说明：$RELEASE_NOTES"
