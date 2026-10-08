#!/bin/sh
set -eu
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -L)"
SKILL_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -L)"
[ -f "$SKILL_DIR/SKILL.md" ] || { printf '校验失败：缺少 SKILL.md。\n' >&2; exit 1; }
SKILL_NAME="${SKILL_DIR##*/}"
FOUND_NAME="$(awk '
  NR == 1 { if ($0 != "---") exit 1; next }
  /^---$/ { exit }
  /^name:[[:space:]]*/ { sub(/^name:[[:space:]]*/, ""); print; exit }
' "$SKILL_DIR/SKILL.md")" || { printf '校验失败：frontmatter 无效。\n' >&2; exit 1; }
[ "$FOUND_NAME" = "$SKILL_NAME" ] || { printf '校验失败：技能名与目录名不一致。\n' >&2; exit 1; }
printf '校验通过：%s。\n' "$SKILL_NAME"
