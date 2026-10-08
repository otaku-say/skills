#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -L)"
SKILL_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -L)"
TOOL="${SKILL_DIR##*/}"
fail() { printf '运行时更新失败：%s\n' "$1" >&2; exit 1; }

case "$TOOL" in aiod-cli|cube-cli) ;; *) fail "不支持的技能目录：$TOOL" ;; esac
[ -n "${HOME:-}" ] || fail '请先设置 HOME'
case "$(uname -m)" in
  x86_64|amd64) HOST_ARCH=amd64 ;;
  aarch64|arm64) HOST_ARCH=arm64 ;;
  *) fail "不支持的处理器架构：$(uname -m)" ;;
esac
IFS= read -r SOURCE_COMMIT < "$SKILL_DIR/RUNTIME_SOURCE_COMMIT" \
  || fail '无法读取 RUNTIME_SOURCE_COMMIT'
case "$SOURCE_COMMIT" in *[!0-9a-fA-F]*|'') fail 'RUNTIME_SOURCE_COMMIT 格式无效' ;; esac
[ "${#SOURCE_COMMIT}" -eq 40 ] || fail 'RUNTIME_SOURCE_COMMIT 必须是 40 位 Git commit'
RUNTIME_HOME="${TEABLE_SKILLS_RUNTIME_HOME:-$HOME/workspace/.cache/otaku-skills-runtime}"
case "$RUNTIME_HOME" in /*) ;; *) fail 'TEABLE_SKILLS_RUNTIME_HOME 必须是绝对路径' ;; esac
RUNTIME_ROOT="$RUNTIME_HOME/$TOOL"
RUNTIME_DIR="$RUNTIME_ROOT/$SOURCE_COMMIT"
MARKER="$RUNTIME_DIR/.$TOOL-runtime-managed"
PAYLOAD_ROOT="$RUNTIME_DIR/bin"
MANIFEST="$SKILL_DIR/bin/SHA256SUMS"
RAW_BASE="${SKILLS_RAW_BASE:-https://raw.githubusercontent.com/otaku-say/skills}"
[ -f "$MANIFEST" ] || fail "缺少校验清单：$MANIFEST"

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v busybox >/dev/null 2>&1; then
    busybox sha256sum "$1" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  else
    fail '校验需要 sha256sum、BusyBox 或 openssl'
  fi
}

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
  fail "无法下载 $TOOL 当前架构运行时"
}

verify_payload() {
  payload_root="$1"
  count=0
  while read -r expected relative extra || [ -n "${expected:-}" ]; do
    [ -n "${expected:-}" ] || continue
    [ -z "${extra:-}" ] || return 1
    case "$expected" in *[!0-9a-fA-F]*|'') return 1 ;; esac
    [ "${#expected}" -eq 64 ] || return 1
    case "$relative" in
      amd64/"$TOOL"|arm64/"$TOOL") ;;
      *) return 1 ;;
    esac
    case "$relative" in "$HOST_ARCH/"*) ;; *) continue ;; esac
    file="$payload_root/$relative"
    [ ! -L "$file" ] && [ -f "$file" ] && [ -x "$file" ] || return 1
    [ "$(hash_file "$file")" = "$expected" ] || return 1
    count=$((count + 1))
  done < "$MANIFEST"
  [ "$count" -eq 1 ]
}

verify_existing() {
  [ ! -L "$RUNTIME_DIR" ] && [ -d "$RUNTIME_DIR" ] && [ -f "$MARKER" ] || return 1
  IFS=' ' read -r installed_commit installed_arch extra < "$MARKER" || return 1
  [ "$installed_commit" = "$SOURCE_COMMIT" ] \
    && [ "$installed_arch" = "$HOST_ARCH" ] \
    && [ -z "${extra:-}" ] || return 1
  verify_payload "$PAYLOAD_ROOT"
}

if [ -e "$RUNTIME_DIR" ] || [ -L "$RUNTIME_DIR" ]; then
  [ ! -L "$RUNTIME_DIR" ] && [ -d "$RUNTIME_DIR" ] \
    || fail "拒绝覆盖非目录或符号链接运行时：$RUNTIME_DIR"
  [ -f "$MARKER" ] || fail "拒绝覆盖没有管理标记的运行时：$RUNTIME_DIR"
  IFS=' ' read -r installed_commit installed_arch extra < "$MARKER" || true
  [ "$installed_commit" = "$SOURCE_COMMIT" ] \
    && [ -z "${extra:-}" ] || fail "运行时标记与版本不匹配：$MARKER"
  case "$installed_arch" in amd64|arm64) ;; *) fail "运行时架构标记无效：$MARKER" ;; esac
  if verify_existing; then
    printf '%s 运行时已就绪：%s\n' "$TOOL" "$RUNTIME_DIR"
    exit 0
  fi
  rm -rf "$RUNTIME_DIR" || fail "无法清理损坏的受管理运行时：$RUNTIME_DIR"
fi

mkdir -p "$RUNTIME_ROOT" || fail "无法创建用户缓存目录：$RUNTIME_ROOT"
attempt=0
TMP="$RUNTIME_ROOT/.$TOOL-update.$$"
while ! (umask 077 && mkdir "$TMP") 2>/dev/null; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 10 ] || fail '无法创建临时运行时目录'
  TMP="$RUNTIME_ROOT/.$TOOL-update.$$.$attempt"
done
cleanup() { [ -z "$TMP" ] || rm -rf "$TMP"; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

mkdir -p "$TMP/bin"
COUNT=0
while read -r expected relative extra || [ -n "${expected:-}" ]; do
  [ -n "${expected:-}" ] || continue
  [ -z "${extra:-}" ] || fail '校验清单格式无效'
  case "$expected" in *[!0-9a-fA-F]*|'') fail "SHA256 格式无效：$relative" ;; esac
  [ "${#expected}" -eq 64 ] || fail "SHA256 长度无效：$relative"
  case "$relative" in
    amd64/"$TOOL"|arm64/"$TOOL") ;;
    *) fail "清单路径无效：$relative" ;;
  esac
  case "$relative" in "$HOST_ARCH/"*) ;; *) continue ;; esac
  output="$TMP/bin/$relative"
  mkdir -p "$(dirname -- "$output")"
  download_file "$RAW_BASE/$SOURCE_COMMIT/$TOOL/bin/$relative" "$output"
  chmod +x "$output" || fail "无法设置执行权限：$relative"
  [ "$(hash_file "$output")" = "$expected" ] || fail "SHA256 不匹配：$relative"
  COUNT=$((COUNT + 1))
done < "$MANIFEST"
[ "$COUNT" -eq 1 ] || fail '当前架构清单必须且只能包含一个 CLI 二进制'
printf '%s %s\n' "$SOURCE_COMMIT" "$HOST_ARCH" > "$TMP/.$TOOL-runtime-managed"
verify_payload "$TMP/bin" || fail '暂存运行时验证失败'
mv "$TMP" "$RUNTIME_DIR" || fail "无法启用已验证运行时：$RUNTIME_DIR"
TMP=""
printf '%s 运行时已安装：%s\n' "$TOOL" "$RUNTIME_DIR"
