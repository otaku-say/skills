#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -L)"
PROFILE_DIR="$ROOT/repository/branch-profiles"
command -v jq >/dev/null 2>&1 || { printf '校验发行 profile 需要 jq。\n' >&2; exit 1; }
[ -d "$PROFILE_DIR" ] || { printf '缺少分支 profile 目录。\n' >&2; exit 1; }
COUNT=0
SEEN="|"

for PROFILE in "$PROFILE_DIR"/*.json; do
  [ -f "$PROFILE" ] || continue
  jq -e . "$PROFILE" >/dev/null || { printf 'JSON 无效：%s\n' "$PROFILE" >&2; exit 1; }
  BRANCH="$(jq -er '.branch | strings | select(length > 0)' "$PROFILE")"
  HISTORY="$(jq -er '.history | strings | select(length > 0)' "$PROFILE")"
  INCLUDE_BINARIES="$(jq -er '.payload.includeBinaries | tostring' "$PROFILE")"
  MIRROR_TREE="$(jq -r '(.mirrorSourceTree // false) | tostring' "$PROFILE")"
  MAX_BYTES="$(jq -r '.limits.packageBytes // .limits.skillPackageBytes // empty' "$PROFILE")"
  RUNTIME_SOURCE="$(jq -r '.payload.runtimeSourceBranch // empty' "$PROFILE")"

  case "$BRANCH" in *[!a-z0-9-]*|'') printf '分支名无效：%s\n' "$BRANCH" >&2; exit 1 ;; esac
  case "$SEEN" in *"|$BRANCH|"*) printf '分支重复：%s\n' "$BRANCH" >&2; exit 1 ;; esac
  SEEN="$SEEN$BRANCH|"
  case "$HISTORY" in source|orphan) ;; *) printf 'history 必须是 source 或 orphan：%s\n' "$PROFILE" >&2; exit 1 ;; esac
  case "$INCLUDE_BINARIES" in true|false) ;; *) printf 'includeBinaries 必须是布尔值：%s\n' "$PROFILE" >&2; exit 1 ;; esac
  case "$MIRROR_TREE" in true|false) ;; *) printf 'mirrorSourceTree 必须是布尔值：%s\n' "$PROFILE" >&2; exit 1 ;; esac
  if [ -n "$MAX_BYTES" ]; then
    case "$MAX_BYTES" in *[!0-9]*|'0') printf '包大小上限必须是正整数：%s\n' "$PROFILE" >&2; exit 1 ;; esac
    [ "$INCLUDE_BINARIES" = false ] || { printf '有包大小上限的 profile 不得内含二进制：%s\n' "$PROFILE" >&2; exit 1; }
  fi
  if [ "$BRANCH" != main ]; then
    [ "$HISTORY" = orphan ] || { printf '兼容分支必须使用 orphan 历史：%s\n' "$PROFILE" >&2; exit 1; }
  fi

  if [ "$MIRROR_TREE" = true ]; then
    [ "$INCLUDE_BINARIES" = false ] && [ "$RUNTIME_SOURCE" = main ] \
      || { printf '完整镜像 profile 必须从 main 获取运行时且排除二进制：%s\n' "$PROFILE" >&2; exit 1; }
    [ -n "$MAX_BYTES" ] || { printf '完整镜像 profile 必须声明包大小上限：%s\n' "$PROFILE" >&2; exit 1; }
    [ -f "$ROOT/README.md" ] && [ -f "$ROOT/AGENTS.md" ] && [ -f "$ROOT/CONTRIBUTING.md" ] \
      || { printf '完整镜像必须包含 README.md、AGENTS.md 和 CONTRIBUTING.md。\n' >&2; exit 1; }
    ARCH_NAMES="$(jq -r '(.payload.archDirectoryNames // []) | join(",")' "$PROFILE")"
    case "$ARCH_NAMES" in *amd64*arm64*|*arm64*amd64*) ;; *) printf '完整镜像必须声明 amd64 和 arm64 二进制目录。\n' >&2; exit 1 ;; esac
    SKILL_COUNT=0
    for SKILL_DIR in "$ROOT"/*; do
      [ -f "$SKILL_DIR/SKILL.md" ] || continue
      SKILL_NAME="${SKILL_DIR##*/}"
      for lifecycle in install update uninstall verify; do
        [ -f "$SKILL_DIR/scripts/$lifecycle.sh" ] \
          || { printf '%s 缺少 scripts/%s.sh。\n' "$SKILL_NAME" "$lifecycle" >&2; exit 1; }
      done
      SKILL_COUNT=$((SKILL_COUNT + 1))
    done
    [ "$SKILL_COUNT" -gt 0 ] || { printf '完整镜像中没有顶层技能。\n' >&2; exit 1; }
    OVERRIDE_LIST="$(jq -r '(.skillOverrides // {}) | to_entries[] | [.key, .value] | @tsv' "$PROFILE")"
    if [ -n "$OVERRIDE_LIST" ]; then
      printf '%s\n' "$OVERRIDE_LIST" | while IFS="$(printf '\t')" read -r SKILL_NAME TEMPLATE; do
        [ -n "$SKILL_NAME" ] || continue
        case "$SKILL_NAME" in *[!a-z0-9-]*|'') printf '覆盖技能名无效：%s\n' "$SKILL_NAME" >&2; exit 1 ;; esac
        case "$TEMPLATE" in /*|..|../*|*/../*|*/..) printf '覆盖模板路径无效：%s\n' "$TEMPLATE" >&2; exit 1 ;; esac
        [ -f "$ROOT/$SKILL_NAME/SKILL.md" ] \
          || { printf '覆盖目标不是顶层技能：%s\n' "$SKILL_NAME" >&2; exit 1; }
        [ -f "$ROOT/$TEMPLATE" ] \
          || { printf '覆盖模板不存在：%s\n' "$TEMPLATE" >&2; exit 1; }
        TEMPLATE_NAME="$(awk -F: '$1 == "name" {sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' "$ROOT/$TEMPLATE")"
        [ "$TEMPLATE_NAME" = "$SKILL_NAME" ] \
          || { printf '覆盖模板技能名不匹配：%s\n' "$TEMPLATE" >&2; exit 1; }
      done
    fi
    FILE_OVERRIDE_LIST="$(jq -r '(.fileOverrides // {}) | to_entries[] | [.key, .value] | @tsv' "$PROFILE")"
    if [ -n "$FILE_OVERRIDE_LIST" ]; then
      printf '%s\n' "$FILE_OVERRIDE_LIST" | while IFS="$(printf '\t')" read -r TARGET TEMPLATE; do
        [ -n "$TARGET" ] || continue
        case "$TARGET" in /*|..|../*|*/../*|*/..|*//*) printf '覆盖目标路径无效：%s\n' "$TARGET" >&2; exit 1 ;; esac
        case "$TARGET" in */*) ;; *) printf '覆盖目标必须位于技能目录：%s\n' "$TARGET" >&2; exit 1 ;; esac
        SKILL_NAME="${TARGET%%/*}"
        case "$SKILL_NAME" in *[!a-z0-9-]*|'') printf '覆盖目标技能名无效：%s\n' "$TARGET" >&2; exit 1 ;; esac
        case "$TEMPLATE" in /*|..|../*|*/../*|*/..) printf '覆盖模板路径无效：%s\n' "$TEMPLATE" >&2; exit 1 ;; esac
        [ -f "$ROOT/$SKILL_NAME/SKILL.md" ] \
          || { printf '覆盖目标不是顶层技能：%s\n' "$SKILL_NAME" >&2; exit 1; }
        [ -f "$ROOT/$TARGET" ] && [ ! -L "$ROOT/$TARGET" ] \
          || { printf '覆盖目标不存在或是符号链接：%s\n' "$TARGET" >&2; exit 1; }
        [ -f "$ROOT/$TEMPLATE" ] && [ ! -L "$ROOT/$TEMPLATE" ] \
          || { printf '覆盖模板不存在或是符号链接：%s\n' "$TEMPLATE" >&2; exit 1; }
      done
    fi
  else
    SKILL_PATH="$(jq -er '.skillPath | strings | select(length > 0)' "$PROFILE")"
    TEMPLATE="$(jq -er '.skillTemplate | strings | select(length > 0)' "$PROFILE")"
    RUNTIME_SOURCE="$(jq -r '.payload.runtimeSourceBranch // empty' "$PROFILE")"
    case "$SKILL_PATH" in /*|..|../*|*/../*|*/..) printf 'skillPath 无效：%s\n' "$SKILL_PATH" >&2; exit 1 ;; esac
    [ -f "$ROOT/$SKILL_PATH/SKILL.md" ] || { printf '技能入口不存在：%s/SKILL.md\n' "$SKILL_PATH" >&2; exit 1; }
    [ -f "$ROOT/$TEMPLATE" ] || { printf 'profile 模板不存在：%s\n' "$TEMPLATE" >&2; exit 1; }
    if [ "$INCLUDE_BINARIES" = false ] && [ -z "$RUNTIME_SOURCE" ]; then
      printf '不带二进制的 profile 必须指定运行时来源：%s\n' "$PROFILE" >&2
      exit 1
    fi
  fi

  if [ "$BRANCH" = teable ]; then
    [ "$MIRROR_TREE" = true ] && [ "$MAX_BYTES" -le 512000 ] \
      || { printf 'Teable profile 必须完整镜像且小于等于 512000 字节。\n' >&2; exit 1; }
    TOOLS_TEMPLATE="$(jq -r '.skillOverrides.tools // empty' "$PROFILE")"
    TOOLS_UPDATE_TEMPLATE="$(jq -r '.fileOverrides["tools/scripts/update.sh"] // empty' "$PROFILE")"
    BUSYBOX_USAGE_TEMPLATE="$(jq -r '.fileOverrides["tools/busybox/USAGE.md"] // empty' "$PROFILE")"
    [ -n "$TOOLS_TEMPLATE" ] && [ -n "$TOOLS_UPDATE_TEMPLATE" ] && [ -n "$BUSYBOX_USAGE_TEMPLATE" ] \
      || { printf 'Teable profile 必须提供 tools 技能及安全文件覆盖。\n' >&2; exit 1; }
    for TEABLE_TEMPLATE in "$TOOLS_TEMPLATE" "$TOOLS_UPDATE_TEMPLATE" "$BUSYBOX_USAGE_TEMPLATE"; do
      if grep -Eiq -e '--set-default-busybox|/bin/busybox|sudo' "$ROOT/$TEABLE_TEMPLATE"; then
        printf 'Teable tools 覆盖模板不得包含系统 BusyBox 替换或提权指引：%s\n' "$TEABLE_TEMPLATE" >&2
        exit 1
      fi
    done
  fi
  COUNT=$((COUNT + 1))
  printf '通过分支 profile：%s\n' "$BRANCH"
done

[ "$COUNT" -gt 0 ] || { printf '没有发现分支 profile。\n' >&2; exit 1; }
printf '已校验 %s 个发行 profile。\n' "$COUNT"
