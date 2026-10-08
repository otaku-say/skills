#!/bin/sh
set -eu

fail() {
  printf '校验失败：%s\n' "$1" >&2
  exit 1
}

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -L)"
SKILL_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -L)"
ROOT="$SKILL_DIR"
ROOT_SET=0
MODE=full
[ "$#" -le 2 ] || fail "用法：sh $0 [技能目录] [--metadata-only]"
for arg in "$@"; do
  case "$arg" in
    --metadata-only) MODE=metadata ;;
    *) [ "$ROOT_SET" -eq 0 ] || fail "技能目录只能指定一次"; ROOT="$arg"; ROOT_SET=1 ;;
  esac
done
[ -d "$ROOT" ] || fail "找不到技能目录：$ROOT"

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
    fail "校验需要 sha256sum、BusyBox 或 openssl"
  fi
}

verify_binary_manifest() {
  manifest="$1"
  payload_root="$2"
  arch="$3"
  skip_payload="${4:-0}"
  [ -f "$manifest" ] || fail "缺少校验清单：$manifest"
  count=0
  while read -r expected relative extra || [ -n "${expected:-}" ]; do
    [ -n "${expected:-}" ] || continue
    [ -z "${extra:-}" ] || fail "校验清单格式无效：$manifest"
    case "$expected" in *[!0-9a-fA-F]*|'') fail "SHA256 格式无效：$relative" ;; esac
    [ "${#expected}" -eq 64 ] || fail "SHA256 长度无效：$relative"
    case "$relative" in
      /*|..|../*|*/../*|*/..|*//*) fail "校验清单路径无效：$relative" ;;
      */"$arch"/*) ;;
      *) fail "清单包含错误架构路径：$relative" ;;
    esac
    count=$((count + 1))
    [ "$skip_payload" -eq 1 ] && continue
    file="$payload_root/$relative"
    [ ! -L "$file" ] && [ -f "$file" ] && [ -x "$file" ] || fail "文件缺失或不可执行：$relative"
    actual="$(hash_file "$file")"
    [ "$actual" = "$expected" ] || fail "SHA256 不匹配：$relative"
  done < "$manifest"
  [ "$count" -gt 0 ] || fail "校验清单为空：$manifest"
}

verify_docs() {
  manifest="$ROOT/DOCS.sha256"
  [ -f "$manifest" ] || fail "缺少文档校验清单：$manifest"
  while read -r expected relative extra || [ -n "${expected:-}" ]; do
    [ -n "${expected:-}" ] || continue
    [ -z "${extra:-}" ] || fail "文档清单格式无效：$manifest"
    case "$relative" in /*|..|../*|*/../*|*/..) fail "文档路径无效：$relative" ;; esac
    case "$expected" in *[!0-9a-fA-F]*|'') fail "文档 SHA256 格式无效：$relative" ;; esac
    [ "${#expected}" -eq 64 ] || fail "文档 SHA256 长度无效：$relative"
    file="$ROOT/$relative"
    [ ! -L "$file" ] && [ -f "$file" ] || fail "文档缺失：$relative"
    actual="$(hash_file "$file")"
    [ "$actual" = "$expected" ] || fail "文档 SHA256 不匹配：$relative"
  done < "$manifest"
}

verify_docs
if [ "$MODE" = metadata ]; then
  verify_binary_manifest "$ROOT/SHA256SUMS.amd64" "" amd64 1
  verify_binary_manifest "$ROOT/SHA256SUMS.arm64" "" arm64 1
  payload_root=""
elif [ -f "$ROOT/RUNTIME_SOURCE_COMMIT" ]; then
  IFS= read -r source_commit < "$ROOT/RUNTIME_SOURCE_COMMIT"
  case "$source_commit" in *[!0-9a-fA-F]*|'') fail "RUNTIME_SOURCE_COMMIT 格式无效" ;; esac
  [ "${#source_commit}" -eq 40 ] || fail "RUNTIME_SOURCE_COMMIT 必须是 40 位 Git commit"
  root_parent="$(CDPATH= cd -- "$ROOT/.." && pwd -L)"
  runtime_dir="$root_parent/.ish-toolbox-runtime/$source_commit"
  payload_root="$runtime_dir/tools"
  runtime_marker="$runtime_dir/.ish-toolbox-runtime-managed"
  [ ! -L "$runtime_dir" ] && [ -f "$runtime_marker" ] || fail "运行时二进制尚未安装；请运行 scripts/install.sh"
  IFS=' ' read -r installed_commit installed_arch extra < "$runtime_marker" || true
  [ "$installed_commit" = "$source_commit" ] && [ "$installed_arch" = "$HOST_ARCH" ] && [ -z "${extra:-}" ] \
    || fail "运行时版本或架构标记不匹配"
  verify_binary_manifest "$ROOT/SHA256SUMS.$HOST_ARCH" "$payload_root" "$HOST_ARCH"
else
  payload_root="$ROOT"
  verify_binary_manifest "$ROOT/SHA256SUMS.$HOST_ARCH" "$payload_root" "$HOST_ARCH"
fi

count=0
for tool_dir in "$ROOT"/*; do
  [ -d "$tool_dir" ] || continue
  tool="${tool_dir##*/}"
  case "$tool" in bin|scripts|references) continue ;; esac
  [ -f "$tool_dir/USAGE.md" ] || fail "$tool 缺少 USAGE.md"
  if [ "$MODE" = full ]; then
    binary="$payload_root/$tool/$HOST_ARCH/$tool"
    [ ! -L "$binary" ] && [ -f "$binary" ] && [ -x "$binary" ] || fail "$tool 缺少可执行的 $HOST_ARCH 二进制"
  fi
  count=$((count + 1))
done
[ "$count" -gt 0 ] || fail "技能目录中没有工具"
if [ "$MODE" = metadata ]; then
  printf '元数据校验通过：%s 个工具说明和全部架构 SHA256 清单。\n' "$count"
else
  printf '校验通过：%s 个工具的 %s 二进制和全部说明文档。\n' "$count" "$HOST_ARCH"
fi
