#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -L)"
SKILL_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -L)"
BIN_DIR="$SKILL_DIR/bin"
TOOL="${SKILL_DIR##*/}"

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

MANIFEST="$BIN_DIR/SHA256SUMS"
[ -f "$MANIFEST" ] || fail "缺少校验清单：$MANIFEST"
MATCH_COUNT=0
while read -r expected relative extra || [ -n "${expected:-}" ]; do
  [ -n "${expected:-}" ] || continue
  [ -z "${extra:-}" ] || fail '校验清单格式无效'
  case "$expected" in *[!0-9a-fA-F]*|'') fail "SHA256 格式无效：$relative" ;; esac
  [ "${#expected}" -eq 64 ] || fail "SHA256 长度无效：$relative"
  case "$relative" in amd64/"$TOOL"|arm64/"$TOOL") ;; *) fail "清单路径无效：$relative" ;; esac
  case "$relative" in "$HOST_ARCH/"*) ;; *) continue ;; esac
  file="$BIN_DIR/$relative"
  [ ! -L "$file" ] && [ -f "$file" ] && [ -x "$file" ] || fail "二进制缺失或不可执行：$relative"
  actual="$(hash_file "$file")"
  [ "$actual" = "$expected" ] || fail "SHA256 不匹配：$relative"
  MATCH_COUNT=$((MATCH_COUNT + 1))
done < "$MANIFEST"
[ "$MATCH_COUNT" -eq 1 ] || fail "校验清单必须包含且只能包含当前架构的二进制"
[ -x "$BIN_DIR/$TOOL" ] || fail "缺少可执行命令 wrapper：$BIN_DIR/$TOOL"
printf '校验通过：%s 的 %s 二进制和命令 wrapper。\n' "$TOOL" "$HOST_ARCH"
