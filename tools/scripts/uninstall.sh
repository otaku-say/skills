#!/bin/sh
set -eu

PREFIX="${HOME:?请先设置 HOME}/.local/share/ish-toolbox"

case "${1:-}" in
  "")
    if [ ! -t 0 ]; then
      printf '非交互卸载请显式传入 --yes。\n' >&2
      exit 2
    fi
    printf '将删除 %s 及工具箱写入的 PATH 配置。输入 yes 继续：' "$PREFIX"
    IFS= read -r answer
    [ "$answer" = yes ] || { printf '已取消。\n'; exit 0; }
    ;;
  --yes) ;;
  *) printf '用法：sh %s [--yes]\n' "$0" >&2; exit 2 ;;
esac

TMP="${TMPDIR:-/tmp}/ish-toolbox-uninstall.$$"
attempt=0
while ! (umask 077 && mkdir "$TMP") 2>/dev/null; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 10 ] || { printf '无法创建临时目录。\n' >&2; exit 1; }
  TMP="${TMPDIR:-/tmp}/ish-toolbox-uninstall.$$.$attempt"
done
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

remove_path_block() {
  profile="$1"
  [ -f "$profile" ] || return 0
  grep -Fq '# BEGIN ish-toolbox PATH' "$profile" || return 0
  awk '
    /^# BEGIN ish-toolbox PATH$/ { skipping=1; next }
    /^# END ish-toolbox PATH$/ { skipping=0; next }
    !skipping { print }
  ' "$profile" > "$TMP/profile"
  cat "$TMP/profile" > "$profile"
}

remove_path_block "$HOME/.profile"
remove_path_block "$HOME/.bashrc"
remove_path_block "$HOME/.bash_profile"
remove_path_block "$HOME/.zshrc"
rm -rf "$PREFIX"
printf '已卸载 ish-toolbox 本地文件和 PATH 配置。\n'
