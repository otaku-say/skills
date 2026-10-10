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
INCLUDE_BINARIES="$(jq -r '.payload.includeBinaries' "$PROFILE")"
MAX_BYTES="$(jq -r '.limits.packageBytes // .limits.skillPackageBytes // empty' "$PROFILE")"
MIRROR_TREE="$(jq -r '(.mirrorSourceTree // false) | tostring' "$PROFILE")"
RUNTIME_SOURCE="$(jq -r '.payload.runtimeSourceBranch // empty' "$PROFILE")"
SOURCE_ROOT="$(CDPATH= cd -- "$SOURCE_ROOT" && pwd -L)"
case "$OUTPUT_DIR" in /*) ;; *) OUTPUT_DIR="$PWD/$OUTPUT_DIR" ;; esac
case "$OUTPUT_DIR/" in "$SOURCE_ROOT/"*) printf '输出目录不得位于源仓库内。\n' >&2; exit 1 ;; esac
if [ -e "$OUTPUT_DIR" ]; then
  [ -d "$OUTPUT_DIR" ] || { printf '输出目标不是目录：%s\n' "$OUTPUT_DIR" >&2; exit 1; }
  [ -z "$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ] \
    || { printf '输出目录必须为空：%s\n' "$OUTPUT_DIR" >&2; exit 1; }
else
  mkdir -p "$OUTPUT_DIR"
fi

if [ "$MIRROR_TREE" = true ]; then
  [ "$INCLUDE_BINARIES" = false ] && [ "$RUNTIME_SOURCE" = main ] \
    || { printf '完整镜像必须排除二进制并从 main 获取运行时。\n' >&2; exit 1; }
  command -v tar >/dev/null 2>&1 || { printf '完整镜像构建需要 tar。\n' >&2; exit 1; }
  command -v file >/dev/null 2>&1 || { printf '完整镜像构建需要 file 检查二进制。\n' >&2; exit 1; }
  command -v sha256sum >/dev/null 2>&1 || { printf '完整镜像构建需要 sha256sum 校验源二进制。\n' >&2; exit 1; }
  ARCHIVE="$OUTPUT_DIR/.source-tree.tar"
  tar --exclude=.git -cf "$ARCHIVE" -C "$SOURCE_ROOT" .
  tar -xf "$ARCHIVE" -C "$OUTPUT_DIR"
  rm -f "$ARCHIVE"
  for required in README.md AGENTS.md CONTRIBUTING.md; do
    [ -f "$OUTPUT_DIR/$required" ] || { printf '完整镜像缺少 %s。\n' "$required" >&2; exit 1; }
  done
  OVERRIDE_LIST="$(jq -r '(.skillOverrides // {}) | to_entries[] | [.key, .value] | @tsv' "$PROFILE")"
  if [ -n "$OVERRIDE_LIST" ]; then
    printf '%s\n' "$OVERRIDE_LIST" | while IFS="$(printf '\t')" read -r skill_name template; do
      [ -n "$skill_name" ] || continue
      case "$skill_name" in *[!a-z0-9-]*|'') printf '覆盖技能名无效：%s\n' "$skill_name" >&2; exit 1 ;; esac
      case "$template" in /*|..|../*|*/../*|*/..) printf '覆盖模板路径无效：%s\n' "$template" >&2; exit 1 ;; esac
      [ -f "$OUTPUT_DIR/$skill_name/SKILL.md" ] \
        || { printf '覆盖目标不是技能：%s\n' "$skill_name" >&2; exit 1; }
      [ -f "$OUTPUT_DIR/$template" ] \
        || { printf '覆盖模板不存在：%s\n' "$template" >&2; exit 1; }
      cp "$OUTPUT_DIR/$template" "$OUTPUT_DIR/$skill_name/SKILL.md"
    done
  fi
  FILE_OVERRIDE_LIST="$(jq -r '(.fileOverrides // {}) | to_entries[] | [.key, .value] | @tsv' "$PROFILE")"
  if [ -n "$FILE_OVERRIDE_LIST" ]; then
    printf '%s\n' "$FILE_OVERRIDE_LIST" | while IFS="$(printf '\t')" read -r target template; do
      [ -n "$target" ] || continue
      case "$target" in /*|..|../*|*/../*|*/..|*//*) printf '覆盖目标路径无效：%s\n' "$target" >&2; exit 1 ;; esac
      case "$target" in */*) ;; *) printf '覆盖目标必须位于技能目录：%s\n' "$target" >&2; exit 1 ;; esac
      skill_name="${target%%/*}"
      case "$skill_name" in *[!a-z0-9-]*|'') printf '覆盖目标技能名无效：%s\n' "$target" >&2; exit 1 ;; esac
      case "$template" in /*|..|../*|*/../*|*/..) printf '覆盖模板路径无效：%s\n' "$template" >&2; exit 1 ;; esac
      [ -f "$OUTPUT_DIR/$skill_name/SKILL.md" ] \
        || { printf '覆盖目标不是技能：%s\n' "$skill_name" >&2; exit 1; }
      [ ! -L "$OUTPUT_DIR/$target" ] && [ -f "$OUTPUT_DIR/$target" ] \
        || { printf '覆盖目标文件不存在或是符号链接：%s\n' "$target" >&2; exit 1; }
      [ ! -L "$OUTPUT_DIR/$template" ] && [ -f "$OUTPUT_DIR/$template" ] \
        || { printf '覆盖模板不存在或是符号链接：%s\n' "$template" >&2; exit 1; }
      cp "$OUTPUT_DIR/$template" "$OUTPUT_DIR/$target"
    done
  fi
  if [ "$BRANCH" = teable ] && [ -d "$OUTPUT_DIR/tools" ]; then
    if grep -ERIl -e '--set-default-busybox|/bin/busybox|sudo' "$OUTPUT_DIR/tools"; then
      printf 'Teable tools 包含不允许的系统 BusyBox 替换或提权指引。\n' >&2
      exit 1
    fi
  fi
  for skill_dir in "$OUTPUT_DIR"/*; do
    [ -f "$skill_dir/DOCS.sha256" ] || continue
    docs_tmp="$skill_dir/.DOCS.sha256"
    : > "$docs_tmp"
    for usage in "$skill_dir"/*/USAGE.md; do
      [ -f "$usage" ] || continue
      relative="${usage#"$skill_dir"/}"
      printf '%s  %s\n' "$(sha256sum "$usage" | awk '{print $1}')" "$relative" >> "$docs_tmp"
    done
    [ -s "$docs_tmp" ] || { printf '%s 的文档清单为空。\n' "${skill_dir##*/}" >&2; exit 1; }
    sort -k2,2 "$docs_tmp" > "$skill_dir/DOCS.sha256"
    rm -f "$docs_tmp"
  done

  verify_arch_manifests() {
    skill_dir="$1"
    found=0
    amd64_count=0
    arm64_count=0
    for manifest in $(find "$skill_dir" -type f -name 'SHA256SUMS*' -print); do
      found=1
      manifest_dir="$(dirname -- "$manifest")"
      while read -r expected relative extra || [ -n "${expected:-}" ]; do
        [ -n "${expected:-}" ] || continue
        [ -z "${extra:-}" ] || { printf '清单格式无效：%s\n' "$manifest" >&2; return 1; }
        case "$expected" in *[!0-9a-fA-F]*|'') printf 'SHA256 格式无效：%s\n' "$relative" >&2; return 1 ;; esac
        [ "${#expected}" -eq 64 ] || { printf 'SHA256 长度无效：%s\n' "$relative" >&2; return 1; }
        case "$relative" in /*|..|../*|*/../*|*/..|*//*) printf '清单路径无效：%s\n' "$relative" >&2; return 1 ;; esac
        case "$relative" in
          amd64/*|*/amd64/*) amd64_count=$((amd64_count + 1)) ;;
          arm64/*|*/arm64/*) arm64_count=$((arm64_count + 1)) ;;
          *) printf '清单路径缺少架构：%s\n' "$relative" >&2; return 1 ;;
        esac
        file="$manifest_dir/$relative"
        [ -f "$file" ] && [ -x "$file" ] || { printf '源二进制缺失或不可执行：%s\n' "$file" >&2; return 1; }
        actual="$(sha256sum "$file" | awk '{print $1}')"
        [ "$actual" = "$expected" ] || { printf '源二进制 SHA256 不匹配：%s\n' "$relative" >&2; return 1; }
      done < "$manifest"
    done
    [ "$found" -eq 1 ] && [ "$amd64_count" -gt 0 ] && [ "$arm64_count" -gt 0 ] \
      || { printf '%s 缺少完整的 amd64/arm64 二进制清单。\n' "${skill_dir##*/}" >&2; return 1; }
  }

  SKILL_COUNT=0
  for skill_dir in "$OUTPUT_DIR"/*; do
    [ -f "$skill_dir/SKILL.md" ] || continue
    skill_name="${skill_dir##*/}"
    for lifecycle in install update uninstall verify; do
      [ -f "$skill_dir/scripts/$lifecycle.sh" ] \
        || { printf '%s 缺少 scripts/%s.sh。\n' "$skill_name" "$lifecycle" >&2; exit 1; }
      sh -n "$skill_dir/scripts/$lifecycle.sh" \
        || { printf '脚本语法错误：%s/scripts/%s.sh\n' "$skill_name" "$lifecycle" >&2; exit 1; }
    done
    arch_dirs="$(find "$skill_dir" \( -type d -o -type l \) \( -name amd64 -o -name arm64 \) -print)"
    if [ -n "$arch_dirs" ]; then
      verify_arch_manifests "$skill_dir"
      grep -Fq RUNTIME_SOURCE_COMMIT "$skill_dir/scripts/update.sh" \
        || { printf '%s 的更新脚本不支持固定运行时来源。\n' "$skill_name" >&2; exit 1; }
      grep -Fq RUNTIME_SOURCE_COMMIT "$skill_dir/scripts/verify.sh" \
        || { printf '%s 的验证脚本不支持缓存运行时。\n' "$skill_name" >&2; exit 1; }
      if ! grep -Fq 'TEABLE_SKILLS_RUNTIME_HOME' "$skill_dir/scripts/update-runtime.sh" 2>/dev/null \
        && ! grep -Fq 'TEABLE_SKILLS_RUNTIME_HOME' "$skill_dir/scripts/update.sh"; then
        printf '%s 的更新脚本未配置 Teable 运行时目录。\n' "$skill_name" >&2
        exit 1
      fi
      if ! grep -Fq '$HOME/workspace/.cache/otaku-skills-runtime' "$skill_dir/scripts/update-runtime.sh" 2>/dev/null \
        && ! grep -Fq '$HOME/workspace/.cache/otaku-skills-runtime' "$skill_dir/scripts/update.sh"; then
        printf '%s 的运行时默认目录不在 Teable 持久 workspace 中。\n' "$skill_name" >&2
        exit 1
      fi
      printf '%s\n' "$SOURCE_COMMIT" > "$skill_dir/RUNTIME_SOURCE_COMMIT"
      for arch_dir in $arch_dirs; do
        case "$arch_dir" in "$skill_dir"/*) ;; *) printf '架构目录越界：%s\n' "$arch_dir" >&2; exit 1 ;; esac
        rm -rf "$arch_dir"
      done
    fi
    SKILL_COUNT=$((SKILL_COUNT + 1))
    if [ "$BRANCH" = teable ] && [ "$skill_name" = tools ]; then
      sh "$skill_dir/scripts/verify.sh" --metadata-only
    fi
    find "$skill_dir/scripts" -type f -name '*.sh' -exec sh -n {} \; \
      || { printf '%s 包含语法错误的维护脚本。\n' "$skill_name" >&2; exit 1; }
  done
  [ "$SKILL_COUNT" -gt 0 ] || { printf '完整镜像中没有顶层技能。\n' >&2; exit 1; }
  [ -z "$(find "$OUTPUT_DIR" \( -type d -o -type l \) \( -name amd64 -o -name arm64 \) -print -quit)" ] \
    || { printf 'Teable 镜像仍包含架构目录。\n' >&2; exit 1; }
  BINARY_REPORT="$(find "$OUTPUT_DIR" -type f -exec file {} + | grep -E 'ELF|Mach-O|PE32' || true)"
  [ -z "$BINARY_REPORT" ] || { printf 'Teable 镜像仍包含编译二进制：\n%s\n' "$BINARY_REPORT" >&2; exit 1; }
  SIZE_BYTES="$(du -sb "$OUTPUT_DIR" | awk '{print $1}')"
  if [ -n "$MAX_BYTES" ] && [ "$SIZE_BYTES" -gt "$MAX_BYTES" ]; then
    printf '完整镜像大小超限：%s 字节，大于 %s。\n' "$SIZE_BYTES" "$MAX_BYTES" >&2
    exit 1
  fi
  printf '已构建 %s 完整镜像：%s 字节，包含 %s 个技能，源 commit %s。\n' \
    "$BRANCH" "$SIZE_BYTES" "$SKILL_COUNT" "$SOURCE_COMMIT"
  exit 0
fi

SKILL_PATH="$(jq -er '.skillPath' "$PROFILE")"
TEMPLATE="$(jq -er '.skillTemplate' "$PROFILE")"

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
    [ -f "$file" ] && [ -x "$file" ] || { printf '源二进制缺失或不可执行：%s\n' "$file" >&2; return 1; }
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
