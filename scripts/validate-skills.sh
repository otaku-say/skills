#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
FAIL=0
COUNT=0

for DIR in "$ROOT"/*/; do
  [ -d "$DIR" ] || continue
  NAME="$(basename "$DIR")"
  case "$NAME" in
    scripts|templates|docs) continue ;;
  esac
  COUNT=$((COUNT + 1))
  FILE="$DIR/SKILL.md"
  if [ ! -f "$FILE" ]; then
    echo "失败 $NAME：缺少 SKILL.md" >&2
    FAIL=1
    continue
  fi
  FRONT="$(awk 'NR == 1 { if ($0 != "---") exit 1; next } /^---$/ { exit } { print }' "$FILE")" || {
    echo "失败 $NAME：YAML frontmatter 缺失或格式不正确" >&2
    FAIL=1
    continue
  }
  SKILL_NAME="$(printf '%s\n' "$FRONT" | awk -F: '$1 == "name" { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }')"
  HAS_DESC="$(printf '%s\n' "$FRONT" | awk -F: '$1 == "description" { found=1 } END { print found+0 }')"
  if [ "$SKILL_NAME" != "$NAME" ]; then
    echo "失败 $NAME：frontmatter name 为 '$SKILL_NAME'，应与目录名一致" >&2
    FAIL=1
  fi
  if [ "$HAS_DESC" -ne 1 ]; then
    echo "失败 $NAME：frontmatter 缺少 description" >&2
    FAIL=1
  fi
  for RESOURCE in references scripts assets bin; do
    if [ -e "$DIR/$RESOURCE" ] && [ ! -d "$DIR/$RESOURCE" ]; then
      echo "失败 $NAME：$RESOURCE 必须是目录" >&2
      FAIL=1
    fi
  done
  if [ -d "$DIR/bin/amd64" ] || [ -d "$DIR/bin/arm64" ]; then
    for ARCH in amd64 arm64; do
      if [ ! -d "$DIR/bin/$ARCH" ]; then
        echo "失败 $NAME：架构二进制目录 bin/$ARCH 缺失" >&2
        FAIL=1
      fi
    done
  fi
  echo "通过 $NAME"
done

[ "$COUNT" -gt 0 ] || { echo "失败：没有找到技能目录" >&2; exit 1; }
[ "$FAIL" -eq 0 ] || exit 1
echo "已校验 $COUNT 个技能目录。"
