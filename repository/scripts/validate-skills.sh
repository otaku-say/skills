#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -L)"
FAIL=0
COUNT=0

fail() {
  printf '失败 %s：%s\n' "$1" "$2" >&2
  FAIL=1
}

for DIR in "$ROOT"/*/; do
  [ -d "$DIR" ] || continue
  NAME="$(basename "$DIR")"
  [ "$NAME" = repository ] && continue
  COUNT=$((COUNT + 1))
  FILE="$DIR/SKILL.md"
  if [ ! -f "$FILE" ]; then
    fail "$NAME" '缺少 SKILL.md'
    continue
  fi
  FRONT="$(awk 'NR == 1 { if ($0 != "---") exit 1; next } /^---$/ { exit } { print }' "$FILE")" || {
    fail "$NAME" 'YAML frontmatter 缺失或格式不正确'
    continue
  }
  SKILL_NAME="$(printf '%s\n' "$FRONT" | awk -F: '$1 == "name" { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }')"
  HAS_DESC="$(printf '%s\n' "$FRONT" | awk -F: '$1 == "description" { found=1 } END { print found+0 }')"
  [ "$SKILL_NAME" = "$NAME" ] || fail "$NAME" "frontmatter name 为 '$SKILL_NAME'，应与目录名一致"
  [ "$HAS_DESC" -eq 1 ] || fail "$NAME" 'frontmatter 缺少 description'

  for RESOURCE in references scripts assets bin; do
    if [ -e "$DIR/$RESOURCE" ] && [ ! -d "$DIR/$RESOURCE" ]; then
      fail "$NAME" "$RESOURCE 必须是目录"
    fi
  done

  for LIFECYCLE in install update uninstall verify; do
    SCRIPT="$DIR/scripts/$LIFECYCLE.sh"
    if [ ! -f "$SCRIPT" ]; then
      fail "$NAME" "缺少必需脚本 scripts/$LIFECYCLE.sh"
      continue
    fi
    sh -n "$SCRIPT" || fail "$NAME" "shell 语法错误：scripts/$LIFECYCLE.sh"
  done
  if [ -f "$DIR/scripts/install.sh" ]; then
    grep -q 'dirname' "$DIR/scripts/install.sh" \
      || fail "$NAME" 'install.sh 必须从脚本位置动态推导技能目录'
    if grep -Eq '(^|[[:space:];|&])(cp|mv)[[:space:]]' "$DIR/scripts/install.sh"; then
      fail "$NAME" 'install.sh 不得复制或移动技能文件；使用 PATH'
    fi
    if grep -Eq '(/home/|~/.local/share|/var/minis/skills)' "$DIR/scripts/install.sh"; then
      fail "$NAME" 'install.sh 不得写死技能安装路径'
    fi
  fi

  for SCRIPT in "$DIR/scripts/"*.sh "$DIR/bin/"*.sh; do
    [ -f "$SCRIPT" ] || continue
    sh -n "$SCRIPT" || fail "$NAME" "shell 语法错误：${SCRIPT#"$DIR"}"
  done

  if [ -d "$DIR/bin/amd64" ] || [ -d "$DIR/bin/arm64" ]; then
    for ARCH in amd64 arm64; do
      if [ ! -d "$DIR/bin/$ARCH" ]; then
        fail "$NAME" "架构二进制目录 bin/$ARCH 缺失"
      fi
    done
  fi
  printf '已检查 %s\n' "$NAME"
done

[ "$COUNT" -gt 0 ] || { printf '失败：没有找到技能目录。\n' >&2; exit 1; }
[ "$FAIL" -eq 0 ] || exit 1
sh "$ROOT/repository/scripts/validate-branch-profiles.sh"
printf '已校验 %s 个技能目录。\n' "$COUNT"
