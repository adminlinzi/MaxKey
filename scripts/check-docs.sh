#!/usr/bin/env bash
# 文档一致性检查：
#   1) 读取 gradle.properties 中的 version（应为纯语义化版本 x.y.z，不含 SNAPSHOT）
#   2) README.md 必须提及该版本号（确保说明文档随版本更新）
#   3) 仓库根必须存在 CHANGELOG.md
# 任一不满足则以 GitHub Actions 错误注解失败。
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="$(grep -E '^version[[:space:]]*=' gradle.properties | head -1 | sed -E 's/^[^=]*=[[:space:]]*//' | tr -d '\r' | tr -d ' ')"
echo "Detected version: ${VERSION}"

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "::error::gradle.properties 的 version='${VERSION}' 不是纯语义化版本 (x.y.z)，发布构建必须使用纯版本号"
  exit 1
fi

if grep -qi "SNAPSHOT" <<<"${VERSION}"; then
  echo "::error::version 包含 SNAPSHOT，发布构建必须使用固定版本号"
  exit 1
fi

if ! grep -q "${VERSION}" README.md; then
  echo "::error::README.md 未提及版本 ${VERSION}，请同步更新说明文档"
  exit 1
fi

if [ ! -f CHANGELOG.md ]; then
  echo "::error::CHANGELOG.md 缺失，请运行 git-cliff 生成"
  exit 1
fi

echo "✅ 文档一致性检查通过（version=${VERSION}）"
