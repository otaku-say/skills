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
  SKILL_PATH="$(jq -er '.skillPath | strings | select(length > 0)' "$PROFILE")"
  HISTORY="$(jq -er '.history | strings | select(length > 0)' "$PROFILE")"
  TEMPLATE="$(jq -er '.skillTemplate | strings | select(length > 0)' "$PROFILE")"
  INCLUDE_BINARIES="$(jq -er '.payload.includeBinaries | tostring' "$PROFILE")"
  MAX_BYTES="$(jq -r '.limits.skillPackageBytes // empty' "$PROFILE")"
  RUNTIME_SOURCE="$(jq -r '.payload.runtimeSourceBranch // empty' "$PROFILE")"

  case "$BRANCH" in *[!a-z0-9-]*|'') printf '分支名无效：%s\n' "$BRANCH" >&2; exit 1 ;; esac
  case "$SKILL_PATH" in /*|..|../*|*/../*|*/..) printf 'skillPath 无效：%s\n' "$SKILL_PATH" >&2; exit 1 ;; esac
  case "$SEEN" in *"|$BRANCH|"*) printf '分支重复：%s\n' "$BRANCH" >&2; exit 1 ;; esac
  SEEN="$SEEN$BRANCH|"
  [ -f "$ROOT/$SKILL_PATH/SKILL.md" ] || { printf '技能入口不存在：%s/SKILL.md\n' "$SKILL_PATH" >&2; exit 1; }
  [ -f "$ROOT/$TEMPLATE" ] || { printf 'profile 模板不存在：%s\n' "$TEMPLATE" >&2; exit 1; }
  case "$HISTORY" in source|orphan) ;; *) printf 'history 必须是 source 或 orphan：%s\n' "$PROFILE" >&2; exit 1 ;; esac
  case "$INCLUDE_BINARIES" in true|false) ;; *) printf 'includeBinaries 必须是布尔值：%s\n' "$PROFILE" >&2; exit 1 ;; esac
  if [ -n "$MAX_BYTES" ]; then
    case "$MAX_BYTES" in *[!0-9]*|'0') printf '包大小上限必须是正整数：%s\n' "$PROFILE" >&2; exit 1 ;; esac
    [ "$INCLUDE_BINARIES" = false ] || { printf '有包大小上限的 profile 不得内含二进制：%s\n' "$PROFILE" >&2; exit 1; }
  fi
  if [ "$INCLUDE_BINARIES" = false ] && [ -z "$RUNTIME_SOURCE" ]; then
    printf '不带二进制的 profile 必须指定运行时来源：%s\n' "$PROFILE" >&2
    exit 1
  fi
  if [ "$BRANCH" != main ]; then
    [ "$HISTORY" = orphan ] || { printf '兼容分支必须使用 orphan 历史：%s\n' "$PROFILE" >&2; exit 1; }
  fi
  if [ "$BRANCH" = teable ]; then
    [ "$MAX_BYTES" -le 512000 ] || { printf 'Teable 包大小上限不能超过 512000 字节。\n' >&2; exit 1; }
    [ "$INCLUDE_BINARIES" = false ] && [ "$RUNTIME_SOURCE" = main ] \
      || { printf 'Teable profile 必须从 main 获取当前架构运行时。\n' >&2; exit 1; }
    case "$TEMPLATE" in *.md.in) ;; *) printf '兼容分支 SKILL 模板不得命名为 SKILL.md：%s\n' "$TEMPLATE" >&2; exit 1 ;; esac
  fi
  COUNT=$((COUNT + 1))
  printf '通过分支 profile：%s\n' "$BRANCH"
done

[ "$COUNT" -gt 0 ] || { printf '没有发现分支 profile。\n' >&2; exit 1; }
printf '已校验 %s 个发行 profile。\n' "$COUNT"
