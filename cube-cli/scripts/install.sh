#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -L)"
SKILL_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -L)"
SKILL_NAME="${SKILL_DIR##*/}"
BIN_DIR="$SKILL_DIR/bin"
PATH_DIR="$BIN_DIR"
PATH_MARKER="# BEGIN $SKILL_NAME PATH"
PATH_END="# END $SKILL_NAME PATH"
[ -n "${HOME:-}" ] || { printf '请先设置 HOME。\n' >&2; exit 1; }
case "$PATH_DIR" in *:*) printf '技能路径包含 PATH 分隔符 ':'。\n' >&2; exit 1 ;; esac
case "$(uname -m)" in
  x86_64|amd64) HOST_ARCH=amd64; OTHER_ARCH=arm64 ;;
  aarch64|arm64) HOST_ARCH=arm64; OTHER_ARCH=amd64 ;;
  *) printf '不支持的处理器架构：%s\n' "$(uname -m)" >&2; exit 1 ;;
esac
if [ -f "$SKILL_DIR/RUNTIME_SOURCE_COMMIT" ]; then
  sh "$SCRIPT_DIR/update-runtime.sh"
  IFS= read -r SOURCE_COMMIT < "$SKILL_DIR/RUNTIME_SOURCE_COMMIT"
  case "$SOURCE_COMMIT" in *[!0-9a-fA-F]*|'') printf 'RUNTIME_SOURCE_COMMIT 格式无效。\n' >&2; exit 1 ;; esac
  [ "${#SOURCE_COMMIT}" -eq 40 ] || { printf 'RUNTIME_SOURCE_COMMIT 必须是 40 位 Git commit。\n' >&2; exit 1; }
  RUNTIME_HOME="${TEABLE_SKILLS_RUNTIME_HOME:-$HOME/workspace/.cache/otaku-skills-runtime}"
  case "$RUNTIME_HOME" in /*) ;; *) printf 'TEABLE_SKILLS_RUNTIME_HOME 必须是绝对路径。\n' >&2; exit 1 ;; esac
  PATH_DIR="$RUNTIME_HOME/$SKILL_NAME/$SOURCE_COMMIT/bin/$HOST_ARCH"
fi
case "$PATH_DIR" in *:*) printf '运行时路径包含 PATH 分隔符 ':'。\n' >&2; exit 1 ;; esac
sh "$SCRIPT_DIR/verify.sh"
[ -f "$PATH_DIR/$SKILL_NAME" ] && [ -x "$PATH_DIR/$SKILL_NAME" ] \
  || { printf 'PATH 目标缺少可执行 CLI：%s\n' "$PATH_DIR/$SKILL_NAME" >&2; exit 1; }

TMP="${TMPDIR:-/tmp}/$SKILL_NAME-install.$$"
attempt=0
while ! (umask 077 && mkdir "$TMP") 2>/dev/null; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 10 ] || { printf '无法创建临时目录。\n' >&2; exit 1; }
  TMP="${TMPDIR:-/tmp}/$SKILL_NAME-install.$$.$attempt"
done
trap 'rm -rf "$TMP"' EXIT
trap 'exit 1' HUP INT TERM


shell_quote() {
  escaped="$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
  printf "'%s'" "$escaped"
}

add_path_block() {
  profile="$1"
  mkdir -p "$(dirname -- "$profile")"
  stage="$TMP/profile"
  if [ -f "$profile" ]; then
    awk -v begin="$PATH_MARKER" -v end="$PATH_END" '
      $0 == begin { if (inside) exit 2; inside=1; next }
      $0 == end { if (!inside) exit 2; inside=0; next }
      !inside { print }
      END { if (inside) exit 2 }
    ' "$profile" > "$stage" || { printf 'PATH 区块不完整：%s\n' "$profile" >&2; exit 1; }
  else
    : > "$stage"
  fi
  quoted_bin="$(shell_quote "$PATH_DIR")"
  {
    printf '%s\n' "$PATH_MARKER"
    printf 'case ":${PATH:-}:" in *:%s:*) ;; *) PATH=%s:${PATH:-} ;; esac\n' "$quoted_bin" "$quoted_bin"
    printf 'export PATH\n%s\n' "$PATH_END"
  } >> "$stage"
  cat "$stage" > "$profile"
}

add_path_block "$HOME/.profile"
add_path_block "$HOME/.ashrc"
add_path_block "$HOME/.bashrc"
add_path_block "$HOME/.bash_profile"
add_path_block "$HOME/.zshrc"
[ ! -L "$BIN_DIR/$OTHER_ARCH" ] || { printf '拒绝删除符号链接目录：%s\n' "$BIN_DIR/$OTHER_ARCH" >&2; exit 1; }
[ ! -e "$BIN_DIR/$OTHER_ARCH" ] || rm -rf "$BIN_DIR/$OTHER_ARCH"
printf '%s PATH 已加入 shell 配置：%s；已保留 %s 架构二进制。\n' "$SKILL_NAME" "$PATH_DIR" "$HOST_ARCH"
