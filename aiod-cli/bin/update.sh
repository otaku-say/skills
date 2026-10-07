#!/bin/sh
set -u

TOOL="aiod-cli"
DIR="$(cd "$(dirname "$0")" && pwd)"
BASE="${AIOD_CLI_RELEASE_BASE:-https://github.com/otaku-say/sandbox-cli/releases/download/latest}"
[ -z "${ISH_TOOLBOX_BIN:-}" ] || PATH="$ISH_TOOLBOX_BIN:$PATH"
export PATH
FORCE=0
case "${1:-}" in
  "") ;;
  --force) FORCE=1 ;;
  *) echo "用法：sh $0 [--force]" >&2; exit 2 ;;
esac

fail() { echo "更新失败：$1" >&2; exit "${2:-1}"; }
command -v curl >/dev/null 2>&1 || fail "需要 curl" 1
AWK_BIN="$(command -v gawk || command -v awk)" || fail "需要 gawk 或 awk" 1
if command -v openssl >/dev/null 2>&1; then
  HASH_MODE=openssl
elif command -v sha256sum >/dev/null 2>&1; then
  HASH_MODE=sha256sum
else
  fail "完整性校验需要 openssl 或 sha256sum" 1
fi
hash_file() {
  if [ "$HASH_MODE" = openssl ]; then
    openssl dgst -sha256 "$1" | "$AWK_BIN" '{print $NF}'
  else
    sha256sum "$1" | "$AWK_BIN" '{print $1}'
  fi
}

case "$(uname -m)" in
  aarch64|arm64) HOST_DIR=arm64 ;;
  x86_64|amd64) HOST_DIR=amd64 ;;
  *) fail "不支持的处理器架构：$(uname -m)" 1 ;;
esac
TMP="${TMPDIR:-/tmp}/$TOOL-update.$$"
(umask 077 && mkdir "$TMP") || fail "无法创建独立临时目录" 1
cleanup() { rm -rf "$TMP"; }
trap cleanup 0
trap 'exit 1' HUP INT TERM
curl -q -fsSL --retry 2 --retry-delay 2 -o "$TMP/SHA256SUMS" "$BASE/SHA256SUMS" || fail "无法下载校验清单" 1

for ARCH in aarch64 x86_64; do
  ASSET="$TOOL-$ARCH-linux-musl"
  case "$ARCH" in aarch64) TARGET_ARCH=arm64 ;; x86_64) TARGET_ARCH=amd64 ;; esac
  TARGET="$DIR/$TARGET_ARCH/$TOOL"
  EXPECTED="$("$AWK_BIN" -v f="$ASSET" '$2 == f { print $1; exit }' "$TMP/SHA256SUMS")"
  [ -n "$EXPECTED" ] || fail "上游校验清单缺少 $ASSET" 1
  if [ -f "$TARGET" ] && [ "$FORCE" -eq 0 ]; then
    CURRENT="$(hash_file "$TARGET")"
    if [ "$CURRENT" = "$EXPECTED" ]; then
      echo "$TARGET_ARCH：已是最新版本"
      continue
    fi
  fi
  curl -q -fsSL --retry 2 --retry-delay 2 -o "$TMP/$ASSET" "$BASE/$ASSET" || fail "无法下载 $ASSET" 1
  ACTUAL="$(hash_file "$TMP/$ASSET")"
  [ "$ACTUAL" = "$EXPECTED" ] || fail "$ASSET 的 SHA256 不匹配" 1
  mkdir -p "$DIR/$TARGET_ARCH" || fail "无法创建目录 $DIR/$TARGET_ARCH" 1
  chmod +x "$TMP/$ASSET" 2>/dev/null || true
  mv "$TMP/$ASSET" "$TARGET" || fail "无法安装 $TARGET" 1
  echo "$TARGET_ARCH：已更新"
done

: > "$TMP/local.SHA256SUMS" || fail "无法创建本地校验清单" 1
for ARCH in aarch64 x86_64; do
  ASSET="$TOOL-$ARCH-linux-musl"
  case "$ARCH" in aarch64) TARGET_ARCH=arm64 ;; x86_64) TARGET_ARCH=amd64 ;; esac
  EXPECTED="$("$AWK_BIN" -v f="$ASSET" '$2 == f { print $1; exit }' "$TMP/SHA256SUMS")"
  printf '%s  %s/%s\n' "$EXPECTED" "$TARGET_ARCH" "$TOOL" >> "$TMP/local.SHA256SUMS" || fail "无法写入本地校验清单" 1
done
mv "$TMP/local.SHA256SUMS" "$DIR/SHA256SUMS" || fail "无法保存本地校验清单" 1
chmod +x "$DIR/$HOST_DIR/$TOOL" 2>/dev/null || true
VERSION="$("$DIR/$HOST_DIR/$TOOL" version)" || fail "更新后的 CLI 无法运行" 1
printf '%s\n' "$VERSION" | "$AWK_BIN" 'NR == 1 { print; exit }'
echo "运行 sh $DIR/verify.sh 可再次校验两个架构的二进制文件。"
