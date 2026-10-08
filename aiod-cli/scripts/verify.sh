#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -L)"
SKILL_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -L)"
TOOL="${SKILL_DIR##*/}"
SKILL_BIN="$SKILL_DIR/bin"
fail() { printf '校验失败：%s\n' "$1" >&2; exit 1; }

case "$(uname -m)" in
  x86_64|amd64) HOST_ARCH=amd64 ;;
  aarch64|arm64) HOST_ARCH=arm64 ;;
  *) fail "不支持的处理器架构：$(uname -m)" ;;
esac

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

BIN_ROOT="$SKILL_BIN"
if [ -f "$SKILL_DIR/RUNTIME_SOURCE_COMMIT" ]; then
  [ -n "${HOME:-}" ] || fail '请先设置 HOME'
  IFS= read -r source_commit < "$SKILL_DIR/RUNTIME_SOURCE_COMMIT" \
    || fail '无法读取 RUNTIME_SOURCE_COMMIT'
  case "$source_commit" in *[!0-9a-fA-F]*|'') fail 'RUNTIME_SOURCE_COMMIT 格式无效' ;; esac
  [ "${#source_commit}" -eq 40 ] || fail 'RUNTIME_SOURCE_COMMIT 必须是 40 位 Git commit'
  runtime_home="${TEABLE_SKILLS_RUNTIME_HOME:-$HOME/workspace/.cache/otaku-skills-runtime}"
  case "$runtime_home" in /*) ;; *) fail 'TEABLE_SKILLS_RUNTIME_HOME 必须是绝对路径' ;; esac
  runtime_dir="$runtime_home/$TOOL/$source_commit"
  runtime_marker="$runtime_dir/.$TOOL-runtime-managed"
  [ ! -L "$runtime_dir" ] && [ -f "$runtime_marker" ] \
    || fail '运行时二进制尚未安装；请运行 scripts/install.sh'
  IFS=' ' read -r installed_commit installed_arch extra < "$runtime_marker" || true
  [ "$installed_commit" = "$source_commit" ] \
    && [ "$installed_arch" = "$HOST_ARCH" ] \
    && [ -z "${extra:-}" ] || fail '运行时版本或架构标记不匹配'
  BIN_ROOT="$runtime_dir/bin"
fi

MANIFEST="$SKILL_BIN/SHA256SUMS"
[ -f "$MANIFEST" ] || fail "缺少校验清单：$MANIFEST"
MATCH_COUNT=0
while read -r expected relative extra || [ -n "${expected:-}" ]; do
  [ -n "${expected:-}" ] || continue
  [ -z "${extra:-}" ] || fail '校验清单格式无效'
  case "$expected" in *[!0-9a-fA-F]*|'') fail "SHA256 格式无效：$relative" ;; esac
  [ "${#expected}" -eq 64 ] || fail "SHA256 长度无效：$relative"
  case "$relative" in amd64/"$TOOL"|arm64/"$TOOL") ;; *) fail "清单路径无效：$relative" ;; esac
  case "$relative" in "$HOST_ARCH/"*) ;; *) continue ;; esac
  file="$BIN_ROOT/$relative"
  [ ! -L "$file" ] && [ -f "$file" ] && [ -x "$file" ] || fail "二进制缺失或不可执行：$relative"
  actual="$(hash_file "$file")"
  [ "$actual" = "$expected" ] || fail "SHA256 不匹配：$relative"
  MATCH_COUNT=$((MATCH_COUNT + 1))
done < "$MANIFEST"
[ "$MATCH_COUNT" -eq 1 ] || fail '校验清单必须包含且只能包含当前架构的二进制'
if [ -f "$SKILL_DIR/RUNTIME_SOURCE_COMMIT" ]; then
  [ -f "$SKILL_BIN/$TOOL" ] && [ -r "$SKILL_BIN/$TOOL" ] \
    || fail "Teable 命令 wrapper 不可读：$SKILL_BIN/$TOOL"
  printf '校验通过：%s 的 %s 缓存运行时和命令 wrapper。\n' "$TOOL" "$HOST_ARCH"
else
  [ -x "$SKILL_BIN/$TOOL" ] || fail "缺少可执行命令 wrapper：$SKILL_BIN/$TOOL"
  printf '校验通过：%s 的 %s 二进制和命令 wrapper。\n' "$TOOL" "$HOST_ARCH"
fi
