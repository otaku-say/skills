#!/bin/sh
set -u

TOOL="cube-cli"
DIR="$(cd "$(dirname "$0")" && pwd)"
BASE="${CUBE_CLI_RELEASE_BASE:-https://github.com/otaku-say/sandbox-cli/releases/download/latest}"
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
attempt=0
while ! (umask 077 && mkdir "$TMP") 2>/dev/null; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 10 ] || fail "无法创建独立临时目录" 1
  TMP="${TMPDIR:-/tmp}/$TOOL-update.$$.$attempt"
done
COMMITTED=0
TRANSACTION=0
ROLLBACK_FAILED=0
rollback() {
  [ "$TRANSACTION" -eq 1 ] && [ "$COMMITTED" -eq 0 ] || return 0
  for ARCH in arm64 amd64; do
    TARGET="$DIR/$ARCH/$TOOL"
    BACKUP="$TMP/backup/$ARCH/$TOOL"
    if [ -f "$BACKUP" ]; then
      cp -p "$BACKUP" "$TARGET" || { echo "警告：无法恢复 $TARGET" >&2; ROLLBACK_FAILED=1; }
    else
      rm -f "$TARGET"
    fi
  done
  if [ -f "$TMP/backup/SHA256SUMS" ]; then
    cp -p "$TMP/backup/SHA256SUMS" "$DIR/SHA256SUMS" || { echo "警告：无法恢复 SHA256SUMS" >&2; ROLLBACK_FAILED=1; }
  else
    rm -f "$DIR/SHA256SUMS"
  fi
}
cleanup() {
  rollback
  if [ "$ROLLBACK_FAILED" -eq 0 ]; then
    rm -rf "$TMP"
  else
    echo "警告：回滚副本保留在 $TMP" >&2
  fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
mkdir -p "$TMP/staged/arm64" "$TMP/staged/amd64" "$TMP/backup/arm64" "$TMP/backup/amd64"
curl -q -fsSL --retry 2 --retry-delay 2 -o "$TMP/SHA256SUMS" "$BASE/SHA256SUMS" || fail "无法下载校验清单" 1

for ARCH in aarch64 x86_64; do
  ASSET="$TOOL-$ARCH-linux-musl"
  case "$ARCH" in aarch64) TARGET_ARCH=arm64 ;; x86_64) TARGET_ARCH=amd64 ;; esac
  TARGET="$DIR/$TARGET_ARCH/$TOOL"
  STAGED="$TMP/staged/$TARGET_ARCH/$TOOL"
  EXPECTED="$("$AWK_BIN" -v f="$ASSET" '$2 == f { print $1; exit }' "$TMP/SHA256SUMS")"
  [ -n "$EXPECTED" ] || fail "上游校验清单缺少 $ASSET" 1
  if [ -f "$TARGET" ] && [ "$FORCE" -eq 0 ] && [ "$(hash_file "$TARGET")" = "$EXPECTED" ]; then
    cp -p "$TARGET" "$STAGED" || fail "无法暂存 $TARGET" 1
    echo "$TARGET_ARCH：已是最新版本"
  else
    curl -q -fsSL --retry 2 --retry-delay 2 -o "$STAGED" "$BASE/$ASSET" || fail "无法下载 $ASSET" 1
    ACTUAL="$(hash_file "$STAGED")"
    [ "$ACTUAL" = "$EXPECTED" ] || fail "$ASSET 的 SHA256 不匹配" 1
    chmod +x "$STAGED" 2>/dev/null || fail "无法设置 $ASSET 的执行权限" 1
    echo "$TARGET_ARCH：已暂存更新"
  fi
  ACTUAL="$(hash_file "$STAGED")"
  [ "$ACTUAL" = "$EXPECTED" ] || fail "$ASSET 的 SHA256 不匹配" 1
done

: > "$TMP/local.SHA256SUMS" || fail "无法创建本地校验清单" 1
for ARCH in aarch64 x86_64; do
  ASSET="$TOOL-$ARCH-linux-musl"
  case "$ARCH" in aarch64) TARGET_ARCH=arm64 ;; x86_64) TARGET_ARCH=amd64 ;; esac
  EXPECTED="$("$AWK_BIN" -v f="$ASSET" '$2 == f { print $1; exit }' "$TMP/SHA256SUMS")"
  printf '%s  %s/%s\n' "$EXPECTED" "$TARGET_ARCH" "$TOOL" >> "$TMP/local.SHA256SUMS" || fail "无法写入本地校验清单" 1
done
chmod +x "$TMP/staged/$HOST_DIR/$TOOL" 2>/dev/null || fail "无法设置本机二进制执行权限" 1
VERSION="$("$TMP/staged/$HOST_DIR/$TOOL" version)" || fail "暂存的 CLI 无法运行" 1

mkdir -p "$DIR/arm64" "$DIR/amd64"
for ARCH in arm64 amd64; do
  TARGET="$DIR/$ARCH/$TOOL"
  [ ! -f "$TARGET" ] || cp -p "$TARGET" "$TMP/backup/$ARCH/$TOOL" || fail "无法备份 $TARGET" 1
done
[ ! -f "$DIR/SHA256SUMS" ] || cp -p "$DIR/SHA256SUMS" "$TMP/backup/SHA256SUMS" || fail "无法备份 SHA256SUMS" 1
TRANSACTION=1
for ARCH in arm64 amd64; do
  mv -f "$TMP/staged/$ARCH/$TOOL" "$DIR/$ARCH/$TOOL" || fail "无法安装 $DIR/$ARCH/$TOOL" 1
done
mv -f "$TMP/local.SHA256SUMS" "$DIR/SHA256SUMS" || fail "无法保存本地校验清单" 1
COMMITTED=1
printf '%s\n' "$VERSION" | "$AWK_BIN" 'NR == 1 { print; exit }'
echo "运行 sh $DIR/verify.sh 可再次校验两个架构的二进制文件。"
