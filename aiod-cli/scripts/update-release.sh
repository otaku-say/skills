#!/bin/sh
# 从上游 Release 下载并原子替换 CLI 二进制。
# 下载优先 wget（BusyBox 环境通常自带），失败自动回退 curl、再回退 uclient-fetch。
# 用法：sh scripts/update-release.sh [--force] [--arch=host|amd64|arm64|both]
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -L)"
SKILL_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -L)"
TOOL="${SKILL_DIR##*/}"
BIN_DIR="$SKILL_DIR/bin"
[ -z "${ISH_TOOLBOX_BIN:-}" ] || PATH="$ISH_TOOLBOX_BIN:${PATH:-}"
export PATH
BASE="${AIOD_CLI_RELEASE_BASE:-https://github.com/otaku-say/sandbox-cli/releases/download/latest}"

FORCE=0
ARCH_SEL=host
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --arch=host|--arch=amd64|--arch=arm64|--arch=both) ARCH_SEL="${arg#--arch=}" ;;
    *) printf '用法：sh %s [--force] [--arch=host|amd64|arm64|both]\n' "$0" >&2; exit 2 ;;
  esac
done

fail() { printf '更新失败：%s\n' "$1" >&2; exit 1; }

case "$(uname -m)" in
  aarch64|arm64) NATIVE_ARCH=arm64 ;;
  x86_64|amd64) NATIVE_ARCH=amd64 ;;
  *) NATIVE_ARCH= ;;
esac

case "$ARCH_SEL" in
  host)
    [ -n "$NATIVE_ARCH" ] || fail "不支持的处理器架构：$(uname -m)"
    ARCHES="$NATIVE_ARCH"
    ;;
  both) ARCHES="amd64 arm64" ;;
  amd64|arm64) ARCHES="$ARCH_SEL" ;;
esac

# 下载链：wget 优先（BusyBox 常见形态），失败级联 curl、再级联 uclient-fetch
download_file() {
  url="$1"
  output="$2"
  if command -v wget >/dev/null 2>&1; then
    if wget -q -O "$output" "$url"; then return 0; fi
    printf 'wget 下载失败，尝试 curl 回退\n' >&2
  fi
  if command -v curl >/dev/null 2>&1; then
    if curl -q -fsSL --retry 2 --retry-delay 2 -o "$output" "$url"; then return 0; fi
    printf 'curl 下载失败，尝试 uclient-fetch 回退\n' >&2
  fi
  if command -v uclient-fetch >/dev/null 2>&1; then
    if uclient-fetch -O "$output" "$url"; then return 0; fi
  fi
  return 1
}

if command -v sha256sum >/dev/null 2>&1; then
  HASH_MODE=sha256sum
elif command -v busybox >/dev/null 2>&1; then
  HASH_MODE=busybox
elif command -v openssl >/dev/null 2>&1; then
  HASH_MODE=openssl
else
  fail '完整性校验需要 sha256sum、BusyBox 或 openssl'
fi
AWK_BIN="$(command -v gawk || command -v awk)" || fail '需要 gawk 或 awk'
hash_file() {
  case "$HASH_MODE" in
    sha256sum) sha256sum "$1" | "$AWK_BIN" '{print $1}' ;;
    busybox) busybox sha256sum "$1" | "$AWK_BIN" '{print $1}' ;;
    openssl) openssl dgst -sha256 "$1" | "$AWK_BIN" '{print $NF}' ;;
  esac
}
arch_asset() {
  case "$1" in
    amd64) printf 'x86_64' ;;
    arm64) printf 'aarch64' ;;
  esac
}

MANIFEST="$BIN_DIR/SHA256SUMS"
TMP=""
attempt=0
candidate="$BIN_DIR/.$TOOL-update.$$"
while ! (umask 077 && mkdir "$candidate") 2>/dev/null; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 10 ] || fail '无法创建同文件系统的更新暂存目录'
  candidate="$BIN_DIR/.$TOOL-update.$$.$attempt"
done
TMP="$candidate"

TRANSACTION=0
COMMITTED=0
rollback() {
  [ "$TRANSACTION" -eq 1 ] && [ "$COMMITTED" -eq 0 ] || return 0
  for arch in $ARCHES; do
    if [ -f "$TMP/backup-$arch" ]; then
      mv -f "$TMP/backup-$arch" "$BIN_DIR/$arch/$TOOL" || printf '警告：无法恢复 %s\n' "$BIN_DIR/$arch/$TOOL" >&2
    else
      rm -f "$BIN_DIR/$arch/$TOOL"
    fi
  done
  if [ -f "$TMP/backup-manifest" ]; then
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

mkdir -p "$TMP/staged"
download_file "$BASE/SHA256SUMS" "$TMP/SHA256SUMS" || fail '无法下载上游校验清单'

for arch in $ARCHES; do
  asset="$TOOL-$(arch_asset "$arch")-linux-musl"
  expected="$("$AWK_BIN" -v f="$asset" '$2 == f { print $1; exit }' "$TMP/SHA256SUMS")"
  [ -n "$expected" ] || fail "上游校验清单缺少 $asset"
  case "$expected" in
    *[!0-9a-fA-F]*) fail "上游 SHA256 格式无效：$asset" ;;
  esac
  [ "${#expected}" -eq 64 ] || fail "上游 SHA256 长度无效：$asset"
  printf '%s\n' "$expected" > "$TMP/expected.$arch"

  target="$BIN_DIR/$arch/$TOOL"
  staged="$TMP/staged/$arch"
  if [ -f "$target" ] && [ "$FORCE" -eq 0 ] && [ "$(hash_file "$target")" = "$expected" ]; then
    cp -p "$target" "$staged" || fail "无法暂存当前版本：$target"
    printf '%s：已是最新版本\n' "$arch"
  else
    download_file "$BASE/$asset" "$staged" || fail "无法下载 $asset"
    [ "$(hash_file "$staged")" = "$expected" ] || fail "$asset 的 SHA256 不匹配"
    chmod +x "$staged" || fail "无法设置 $asset 的执行权限"
    printf '%s：已暂存更新\n' "$arch"
  fi
  [ "$(hash_file "$staged")" = "$expected" ] || fail "$asset 的 SHA256 不匹配"
done

# 仅对与运行主机同架构的暂存件做启动自检（跨架构二进制无法在本机执行）
VERSION=""
for arch in $ARCHES; do
  if [ "$arch" = "$NATIVE_ARCH" ]; then
    VERSION="$("$TMP/staged/$arch" version)" || fail '暂存的 CLI 无法运行'
    break
  fi
done

# 组装本地校验清单：受管架构原地替换，未受管行原样保留
: > "$TMP/manifest.new"
if [ -f "$MANIFEST" ]; then
  while read -r h p rest || [ -n "${h:-}" ]; do
    [ -n "${h:-}" ] || continue
    hit=0
    for arch in $ARCHES; do
      if [ "$p" = "$arch/$TOOL" ]; then
        printf '%s  %s\n' "$(cat "$TMP/expected.$arch")" "$p" >> "$TMP/manifest.new"
        : > "$TMP/sealed.$arch"
        hit=1
        break
      fi
    done
    if [ "$hit" -eq 0 ]; then
      printf '%s  %s\n' "$h" "$p" >> "$TMP/manifest.new"
    fi
  done < "$MANIFEST"
fi
for arch in $ARCHES; do
  if [ ! -f "$TMP/sealed.$arch" ]; then
    printf '%s  %s/%s\n' "$(cat "$TMP/expected.$arch")" "$arch" "$TOOL" >> "$TMP/manifest.new"
  fi
done

for arch in $ARCHES; do
  [ ! -L "$BIN_DIR/$arch" ] || fail "拒绝写入符号链接目录：$BIN_DIR/$arch"
  mkdir -p "$BIN_DIR/$arch" || fail "无法创建目录：$BIN_DIR/$arch"
  target="$BIN_DIR/$arch/$TOOL"
  if [ -f "$target" ]; then
    cp -p "$target" "$TMP/backup-$arch" || fail "无法备份 $target"
  fi
done
if [ -f "$MANIFEST" ]; then
  cp -p "$MANIFEST" "$TMP/backup-manifest" || fail '无法备份本地校验清单'
fi
TRANSACTION=1
for arch in $ARCHES; do
  mv -f "$TMP/staged/$arch" "$BIN_DIR/$arch/$TOOL" || fail "无法更新 $BIN_DIR/$arch/$TOOL"
done
mv -f "$TMP/manifest.new" "$MANIFEST" || fail '无法保存本地校验清单'
sh "$SCRIPT_DIR/verify.sh"
COMMITTED=1
if [ -n "$VERSION" ]; then
  printf '%s\n' "$VERSION" | "$AWK_BIN" 'NR == 1 { print; exit }'
fi
printf '已更新 %s（架构：%s）\n' "$TOOL" "$ARCHES"
