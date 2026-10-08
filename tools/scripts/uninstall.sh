#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -L)"
SKILL_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -L)"
SKILLS_DIR="$(CDPATH= cd -- "$SKILL_DIR/.." && pwd -L)"
YES=0
PURGE_RUNTIME=0
for arg in "$@"; do
  case "$arg" in
    --yes) YES=1 ;;
    --purge-runtime) PURGE_RUNTIME=1 ;;
    *) printf '用法：sh %s [--yes] [--purge-runtime]\n' "$0" >&2; exit 2 ;;
  esac
done

if [ "$YES" -eq 0 ]; then
  if [ ! -t 0 ]; then
    printf '非交互卸载请显式传入 --yes。\n' >&2
    exit 2
  fi
  if [ "$PURGE_RUNTIME" -eq 1 ]; then
    printf '将移除此技能写入的 PATH 配置，并删除所有带工具箱管理标记的版本化运行时目录。输入 yes 继续：'
  else
    printf '将移除此技能写入的 PATH 配置；保留技能文件和二进制。输入 yes 继续：'
  fi
  IFS= read -r answer
  [ "$answer" = yes ] || { printf '已取消。\n'; exit 0; }
fi

[ -n "${HOME:-}" ] || { printf '请先设置 HOME。\n' >&2; exit 1; }
TMP="${TMPDIR:-/tmp}/ish-toolbox-uninstall.$$"
attempt=0
while ! (umask 077 && mkdir "$TMP") 2>/dev/null; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 10 ] || { printf '无法创建临时目录。\n' >&2; exit 1; }
  TMP="${TMPDIR:-/tmp}/ish-toolbox-uninstall.$$.$attempt"
done
trap 'rm -rf "$TMP"' EXIT
trap 'exit 1' HUP INT TERM

RUNTIME_ROOT="$SKILLS_DIR/.ish-toolbox-runtime"
if [ "$PURGE_RUNTIME" -eq 1 ] && [ -e "$RUNTIME_ROOT" ]; then
  [ ! -L "$RUNTIME_ROOT" ] && [ -d "$RUNTIME_ROOT" ] \
    || { printf '拒绝清理非目录或符号链接：%s\n' "$RUNTIME_ROOT" >&2; exit 1; }
  for runtime_dir in "$RUNTIME_ROOT"/*; do
    [ -e "$runtime_dir" ] || continue
    [ ! -L "$runtime_dir" ] && [ -d "$runtime_dir" ] \
      || { printf '拒绝删除非目录或符号链接：%s\n' "$runtime_dir" >&2; exit 1; }
    marker="$runtime_dir/.ish-toolbox-runtime-managed"
    [ -f "$marker" ] || { printf '拒绝删除没有管理标记的目录：%s\n' "$runtime_dir" >&2; exit 1; }
    IFS=' ' read -r managed_commit managed_arch extra < "$marker" || true
    case "$managed_commit" in *[!0-9a-fA-F]*|'') printf '运行时版本标记无效：%s\n' "$marker" >&2; exit 1 ;; esac
    [ "${#managed_commit}" -eq 40 ] || { printf '运行时版本标记无效：%s\n' "$marker" >&2; exit 1; }
    [ "${runtime_dir##*/}" = "$managed_commit" ] \
      || { printf '运行时目录名与标记不匹配：%s\n' "$runtime_dir" >&2; exit 1; }
    case "$managed_arch" in amd64|arm64) ;; *) printf '运行时架构标记无效：%s\n' "$marker" >&2; exit 1 ;; esac
    [ -z "${extra:-}" ] || { printf '运行时标记格式无效：%s\n' "$marker" >&2; exit 1; }
  done
fi

remove_path_block() {
  profile="$1"
  [ -f "$profile" ] || return 0
  grep -Fq '# BEGIN ish-toolbox PATH' "$profile" || return 0
  awk '
    /^# BEGIN ish-toolbox PATH$/ { if (inside) exit 2; inside=1; next }
    /^# END ish-toolbox PATH$/ { if (!inside) exit 2; inside=0; next }
    !inside { print }
    END { if (inside) exit 2 }
  ' "$profile" > "$TMP/profile" || {
    printf 'shell 配置中的 PATH 区块不完整：%s\n' "$profile" >&2
    return 1
  }
  cat "$TMP/profile" > "$profile"
}

remove_path_block "$HOME/.profile"
remove_path_block "$HOME/.ashrc"
remove_path_block "$HOME/.bashrc"
remove_path_block "$HOME/.bash_profile"
remove_path_block "$HOME/.zshrc"

if [ "$PURGE_RUNTIME" -eq 1 ] && [ -d "$RUNTIME_ROOT" ]; then
  for runtime_dir in "$RUNTIME_ROOT"/*; do
    [ -e "$runtime_dir" ] || continue
    rm -rf "$runtime_dir"
  done
  rmdir "$RUNTIME_ROOT" 2>/dev/null || true
fi
printf '已清理工具箱 PATH 配置。\n'
