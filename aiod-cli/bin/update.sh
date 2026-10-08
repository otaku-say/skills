#!/bin/sh
set -eu

TOOL=aiod-cli
DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -L)"
[ -z "${ISH_TOOLBOX_BIN:-}" ] || PATH="$ISH_TOOLBOX_BIN:${PATH:-}"
export PATH
case "$(uname -m)" in
  aarch64|arm64) HOST_DIR=arm64; ASSET_ARCH=aarch64 ;;
  x86_64|amd64) HOST_DIR=amd64; ASSET_ARCH=x86_64 ;;
  *) printf '更新失败：不支持的处理器架构：%s\n' "$(uname -m)" >&2; exit 1 ;;
esac
BASE="${AIOD_CLI_RELEASE_BASE:-https://github.com/otaku-say/sandbox-cli/releases/download/latest}"
FORCE=0
case "${1:-}" in
  '') ;;
  --force) FORCE=1 ;;
  *) printf '用法：sh %s [--force]\n' "$0" >&2; exit 2 ;;
esac

fail() { printf '更新失败：%s\n' "$1" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || fail '需要 curl'
AWK_BIN="$(command -v gawk || command -v awk)" || fail '需要 gawk 或 awk'
if command -v sha256sum >/dev/null 2>&1; then
  HASH_MODE=sha256sum
elif command -v busybox >/dev/null 2>&1; then
  HASH_MODE=busybox
elif command -v openssl >/dev/null 2>&1; then
  HASH_MODE=openssl
else
  fail '完整性校验需要 sha256sum、BusyBox 或 openssl'
fi
hash_file() {
  case "$HASH_MODE" in
    sha256sum) sha256sum "$1" | "$AWK_BIN" '{print $1}' ;;
    busybox) busybox sha256sum "$1" | "$AWK_BIN" '{print $1}' ;;
    openssl) openssl dgst -sha256 "$1" | "$AWK_BIN" '{print $NF}' ;;
  esac
}

TMP=""
attempt=0
candidate="$DIR/.$TOOL-update.$$"
while ! (umask 077 && mkdir "$candidate") 2>/dev/null; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 10 ] || fail '无法创建同文件系统的更新暂存目录'
  candidate="$DIR/.$TOOL-update.$$.$attempt"
done
TMP="$candidate"
TRANSACTION=0
COMMITTED=0
HAD_BINARY=0
HAD_MANIFEST=0
TARGET="$DIR/$HOST_DIR/$TOOL"
MANIFEST="$DIR/SHA256SUMS"

rollback() {
  [ "$TRANSACTION" -eq 1 ] && [ "$COMMITTED" -eq 0 ] || return 0
  if [ "$HAD_BINARY" -eq 1 ]; then
    mv -f "$TMP/backup-binary" "$TARGET" || printf '警告：无法恢复 %s\n' "$TARGET" >&2
  else
    rm -f "$TARGET"
  fi
  if [ "$HAD_MANIFEST" -eq 1 ]; then
    mv -f "$TMP/backup-manifest" "$MANIFEST" || printf '警告：无法恢复 %s\n' "$MANIFEST" >&2
  else
    rm -f "$MANIFEST"
  fi
}
cleanup() {
  rollback
  [ -z "$TMP" ] || rm -rf "$TMP"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

mkdir -p "$TMP/staged" "$DIR/$HOST_DIR"
[ ! -L "$DIR/$HOST_DIR" ] || fail "拒绝写入符号链接目录：$DIR/$HOST_DIR"
curl -q -fsSL --retry 2 --retry-delay 2 -o "$TMP/SHA256SUMS" "$BASE/SHA256SUMS" \
  || fail '无法下载上游校验清单'
ASSET="$TOOL-$ASSET_ARCH-linux-musl"
EXPECTED="$("$AWK_BIN" -v f="$ASSET" '$2 == f { print $1; exit }' "$TMP/SHA256SUMS")"
[ -n "$EXPECTED" ] || fail "上游校验清单缺少 $ASSET"
case "$EXPECTED" in *[!0-9a-fA-F]*) fail "上游 SHA256 格式无效：$ASSET" ;; esac
[ "${#EXPECTED}" -eq 64 ] || fail "上游 SHA256 长度无效：$ASSET"

STAGED="$TMP/staged/$TOOL"
if [ -f "$TARGET" ] && [ "$FORCE" -eq 0 ] && [ "$(hash_file "$TARGET")" = "$EXPECTED" ]; then
  cp -p "$TARGET" "$STAGED" || fail "无法暂存当前版本：$TARGET"
  printf '%s：已是最新版本\n' "$HOST_DIR"
else
  curl -q -fsSL --retry 2 --retry-delay 2 -o "$STAGED" "$BASE/$ASSET" \
    || fail "无法下载 $ASSET"
  [ "$(hash_file "$STAGED")" = "$EXPECTED" ] || fail "$ASSET 的 SHA256 不匹配"
  chmod +x "$STAGED" || fail "无法设置 $ASSET 的执行权限"
  printf '%s：已暂存更新\n' "$HOST_DIR"
fi
[ "$(hash_file "$STAGED")" = "$EXPECTED" ] || fail "$ASSET 的 SHA256 不匹配"
VERSION="$("$STAGED" version)" || fail '暂存的 CLI 无法运行'
printf '%s  %s/%s\n' "$EXPECTED" "$HOST_DIR" "$TOOL" > "$TMP/local.SHA256SUMS"
[ ! -f "$TARGET" ] || { cp -p "$TARGET" "$TMP/backup-binary" || fail "无法备份 $TARGET"; HAD_BINARY=1; }
[ ! -f "$MANIFEST" ] || { cp -p "$MANIFEST" "$TMP/backup-manifest" || fail '无法备份本地校验清单'; HAD_MANIFEST=1; }
TRANSACTION=1
mv -f "$STAGED" "$TARGET" || fail "无法更新 $TARGET"
mv -f "$TMP/local.SHA256SUMS" "$MANIFEST" || fail '无法保存本地校验清单'
sh "$DIR/verify.sh"
COMMITTED=1
printf '%s\n' "$VERSION" | "$AWK_BIN" 'NR == 1 { print; exit }'
