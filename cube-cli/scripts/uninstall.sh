#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -L)"
SKILL_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -L)"
SKILL_NAME="${SKILL_DIR##*/}"
PATH_MARKER="# BEGIN $SKILL_NAME PATH"
PATH_END="# END $SKILL_NAME PATH"
[ -n "${HOME:-}" ] || { printf '请先设置 HOME。\n' >&2; exit 1; }

TMP="${TMPDIR:-/tmp}/$SKILL_NAME-uninstall.$$"
attempt=0
while ! (umask 077 && mkdir "$TMP") 2>/dev/null; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 10 ] || { printf '无法创建临时目录。\n' >&2; exit 1; }
  TMP="${TMPDIR:-/tmp}/$SKILL_NAME-uninstall.$$.$attempt"
done
trap 'rm -rf "$TMP"' EXIT
trap 'exit 1' HUP INT TERM


remove_path_block() {
  profile="$1"
  [ -f "$profile" ] || return 0
  grep -Fq "$PATH_MARKER" "$profile" || return 0
  awk -v begin="$PATH_MARKER" -v end="$PATH_END" '
    $0 == begin { if (inside) exit 2; inside=1; next }
    $0 == end { if (!inside) exit 2; inside=0; next }
    !inside { print }
    END { if (inside) exit 2 }
  ' "$profile" > "$TMP/profile" || { printf 'PATH 区块不完整：%s\n' "$profile" >&2; return 1; }
  cat "$TMP/profile" > "$profile"
}

remove_path_block "$HOME/.profile"
remove_path_block "$HOME/.ashrc"
remove_path_block "$HOME/.bashrc"
remove_path_block "$HOME/.bash_profile"
remove_path_block "$HOME/.zshrc"
printf '已清理 %s 的 PATH 配置；技能文件由 Skills CLI 管理。\n' "$SKILL_NAME"
