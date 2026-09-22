#!/bin/zsh
# 重新生成 TGReduxKitDemo.xcodeproj（XcodeGen）。
#
# 用法：
#     cd Examples/TGReduxKitDemo
#     ./regenerate.sh
#
# 为什么要有这个脚本，而不是直接跑 `xcodegen generate` —— 两个坑：
#
#   1. **`USER` 未设置。** 本机 shell 环境里 `USER` 是空的（`whoami` / `id -un` 正常返回
#      用户名，但 `USER` 变量不存在）。XcodeGen 读 `USER`，取不到就打印
#      `Couldn't find current username` 然后 exit 2，**什么都不生成**。
#      看起来像权限或沙盒问题，其实不是（关掉沙盒一样失败）。
#
#   2. **XcodeGen 不生成 `Package.resolved`。** 该文件钉住了依赖的解析版本
#      （当前 Factory → 2.5.3, revision ccc898f）。直接生成会让它消失，
#      于是 Xcode 下次打开时重新解析依赖，可能拉到不同版本。
#      脚本先备份、生成后还原。
#
# 前提：`../../../TGNavigationStack` 必须存在。
#       XcodeGen 会校验本地包路径，缺失时直接报
#       `Spec validation error: Invalid local package "TGNavigationStack"`。
#       这不是本脚本能绕过的 —— 仓库不在本机时，Demo 本来就无法构建。

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$HERE/TGReduxKitDemo.xcodeproj"
RESOLVED="$PROJECT/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "错误：未找到 xcodegen。请先 brew install xcodegen" >&2
  exit 1
fi

# --- 备份 Package.resolved（XcodeGen 不生成它）---
BACKUP=""
if [[ -f "$RESOLVED" ]]; then
  BACKUP="$(mktemp)"
  cp "$RESOLVED" "$BACKUP"
  echo "已备份 Package.resolved"
fi

restore() {
  if [[ -n "$BACKUP" && -f "$BACKUP" ]]; then
    mkdir -p "$(dirname "$RESOLVED")"
    cp "$BACKUP" "$RESOLVED"
    rm -f "$BACKUP"
    echo "已还原 Package.resolved"
  fi
}
trap restore EXIT

# --- 生成（USER 必须显式提供）---
cd "$HERE"
USER="$(id -un)" xcodegen generate --spec project.yml

echo "完成：$PROJECT"
