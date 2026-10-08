#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -L)"
PROFILE_NAME="${1:-}"
SOURCE_ROOT="${2:-$ROOT}"
OUTPUT_DIR="${3:-}"
SOURCE_COMMIT="${4:-}"
[ -n "$PROFILE_NAME" ] && [ -n "$OUTPUT_DIR" ] && [ -n "$SOURCE_COMMIT" ] || {
  printf '用法：sh %s <profile> <source-root> <empty-output-dir> <source-commit>\n' "$0" >&2
  exit 2
}
command -v jq >/dev/null 2>&1 || { printf '分支构建需要 jq。\n' >&2; exit 1; }
command -v cp >/dev/null 2>&1 || { printf '分支构建需要 cp。\n' >&2; exit 1; }
case "$SOURCE_COMMIT" in *[!0-9a-fA-F]*|'') printf 'source commit 格式无效。\n' >&2; exit 1 ;; esac
[ "${#SOURCE_COMMIT}" -eq 40 ] || { printf 'source commit 必须是 40 位 Git commit。\n' >&2; exit 1; }

PROFILE="$ROOT/repository/branch-profiles/$PROFILE_NAME.json"
[ -f "$PROFILE" ] || { printf '找不到 profile：%s\n' "$PROFILE" >&2; exit 1; }
BRANCH="$(jq -er '.branch' "$PROFILE")"
SKILL_PATH="$(jq -er '.skillPath' "$PROFILE")"
INCLUDE_BINARIES="$(jq -r '.payload.includeBinaries' "$PROFILE")"
MAX_BYTES="$(jq -r '.limits.skillPackageBytes // empty' "$PROFILE")"
TEMPLATE="$(jq -er '.skillTemplate' "$PROFILE")"
RUNTIME_SOURCE="$(jq -r '.payload.runtimeSourceBranch // empty' "$PROFILE")"
SOURCE_ROOT="$(CDPATH= cd -- "$SOURCE_ROOT" && pwd -L)"
[ -d "$SOURCE_ROOT/$SKILL_PATH" ] || { printf '源技能目录不存在：%s\n' "$SKILL_PATH" >&2; exit 1; }
case "$OUTPUT_DIR" in /*) ;; *) OUTPUT_DIR="$PWD/$OUTPUT_DIR" ;; esac
if [ -e "$OUTPUT_DIR" ]; then
  [ -d "$OUTPUT_DIR" ] || { printf '输出目标不是目录：%s\n' "$OUTPUT_DIR" >&2; exit 1; }
  [ -z "$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ] \
    || { printf '输出目录必须为空：%s\n' "$OUTPUT_DIR" >&2; exit 1; }
else
  mkdir -p "$OUTPUT_DIR"
fi

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v busybox >/dev/null 2>&1; then
    busybox sha256sum "$1" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  else
    printf '哈希检查需要 sha256sum、BusyBox 或 openssl。\n' >&2
    exit 1
  fi
}

verify_arch() {
  arch="$1"
  manifest="$SOURCE_ROOT/$SKILL_PATH/SHA256SUMS.$arch"
  [ -f "$manifest" ] || { printf '缺少清单：%s\n' "$manifest" >&2; return 1; }
  count=0
  while read -r expected relative extra || [ -n "${expected:-}" ]; do
    [ -n "${expected:-}" ] || continue
    [ -z "${extra:-}" ] || { printf '清单格式无效：%s\n' "$manifest" >&2; return 1; }
    case "$relative" in /*|..|../*|*/../*|*/..|*//*) printf '清单路径无效：%s\n' "$relative" >&2; return 1 ;; esac
    case "$relative" in */"$arch"/*) ;; *) printf '清单含错误架构路径：%s\n' "$relative" >&2; return 1 ;; esac
    file="$SOURCE_ROOT/$SKILL_PATH/$relative"
    [ -f "$file" ] && [ -x "$file" ] || { printf '源二进制缺失或不可执行：%s\n' "$relative" >&2; return 1; }
    [ "$(hash_file "$file")" = "$expected" ] || { printf '源二进制 SHA256 不匹配：%s\n' "$relative" >&2; return 1; }
    count=$((count + 1))
  done < "$manifest"
  [ "$count" -gt 0 ] || { printf '架构清单为空：%s\n' "$manifest" >&2; return 1; }
}

if [ "$SKILL_PATH" = tools ]; then
  sh "$SOURCE_ROOT/$SKILL_PATH/scripts/verify.sh" --metadata-only
  verify_arch amd64
  verify_arch arm64
fi

OUTPUT_SKILL="$OUTPUT_DIR/$SKILL_PATH"
mkdir -p "$OUTPUT_SKILL"
cp -a "$SOURCE_ROOT/$SKILL_PATH/." "$OUTPUT_SKILL/"
if [ "$INCLUDE_BINARIES" = false ]; then
  for tool_dir in "$OUTPUT_SKILL"/*; do
    [ -f "$tool_dir/USAGE.md" ] || continue
    rm -rf "$tool_dir/amd64" "$tool_dir/arm64"
  done
  [ -n "$RUNTIME_SOURCE" ] || { printf 'profile 未声明运行时来源。\n' >&2; exit 1; }
  cp "$ROOT/$TEMPLATE" "$OUTPUT_SKILL/SKILL.md"
  printf '%s\n' "$SOURCE_COMMIT" > "$OUTPUT_SKILL/RUNTIME_SOURCE_COMMIT"
fi

DOCS_TMP="$OUTPUT_DIR/.DOCS.sha256"
: > "$DOCS_TMP"
for usage in "$OUTPUT_SKILL"/*/USAGE.md; do
  [ -f "$usage" ] || continue
  relative="${usage#"$OUTPUT_SKILL"/}"
  printf '%s  %s\n' "$(hash_file "$usage")" "$relative" >> "$DOCS_TMP"
done
[ -s "$DOCS_TMP" ] || { printf '构建包中没有 USAGE.md。\n' >&2; exit 1; }
sort -k2,2 "$DOCS_TMP" > "$OUTPUT_SKILL/DOCS.sha256"
rm -f "$DOCS_TMP"

for script in "$OUTPUT_SKILL/scripts/"*.sh; do
  [ -f "$script" ] || continue
  sh -n "$script" || { printf '生成脚本语法错误：%s\n' "$script" >&2; exit 1; }
done
sh "$OUTPUT_SKILL/scripts/verify.sh" --metadata-only
if [ "$INCLUDE_BINARIES" = false ]; then
  for tool_dir in "$OUTPUT_SKILL"/*; do
    [ -f "$tool_dir/USAGE.md" ] || continue
    [ ! -e "$tool_dir/amd64" ] && [ ! -e "$tool_dir/arm64" ] \
      || { printf '轻量包仍包含架构目录：%s\n' "$tool_dir" >&2; exit 1; }
  done
fi

SIZE_BYTES="$(du -sb "$OUTPUT_SKILL" | awk '{print $1}')"
if [ -n "$MAX_BYTES" ] && [ "$SIZE_BYTES" -gt "$MAX_BYTES" ]; then
  printf '包大小超限：%s 字节，大于 %s。\n' "$SIZE_BYTES" "$MAX_BYTES" >&2
  exit 1
fi
printf '已构建 %s 分支技能包：%s 字节，源 commit %s。\n' "$BRANCH" "$SIZE_BYTES" "$SOURCE_COMMIT"
