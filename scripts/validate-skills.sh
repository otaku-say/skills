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
    echo "FAIL $NAME: missing SKILL.md" >&2
    FAIL=1
    continue
  fi
  FRONT="$(awk 'NR == 1 { if ($0 != "---") exit 1; next } /^---$/ { exit } { print }' "$FILE")" || {
    echo "FAIL $NAME: invalid or missing YAML frontmatter" >&2
    FAIL=1
    continue
  }
  SKILL_NAME="$(printf '%s\n' "$FRONT" | awk -F: '$1 == "name" { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }')"
  HAS_DESC="$(printf '%s\n' "$FRONT" | awk -F: '$1 == "description" { found=1 } END { print found+0 }')"
  if [ "$SKILL_NAME" != "$NAME" ]; then
    echo "FAIL $NAME: frontmatter name is '$SKILL_NAME'" >&2
    FAIL=1
  fi
  if [ "$HAS_DESC" -ne 1 ]; then
    echo "FAIL $NAME: missing frontmatter description" >&2
    FAIL=1
  fi
  for RESOURCE in references scripts assets bin; do
    if [ -e "$DIR/$RESOURCE" ] && [ ! -d "$DIR/$RESOURCE" ]; then
      echo "FAIL $NAME: $RESOURCE must be a directory" >&2
      FAIL=1
    fi
  done
  echo "OK   $NAME"
done

[ "$COUNT" -gt 0 ] || { echo "FAIL: no skill directories found" >&2; exit 1; }
[ "$FAIL" -eq 0 ] || exit 1
echo "Validated $COUNT skill directories."
