#!/bin/sh
set -eu

RAW_BASE="${ISH_TOOLBOX_RAW_BASE:-https://raw.githubusercontent.com/otaku-say/skills}"

fail() {
  printf '更新失败：%s\n' "$1" >&2
  exit 1
}

[ "$#" -eq 0 ] || fail "用法：sh $0"
[ -n "${HOME:-}" ] || fail "请先设置 HOME"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -L)"
SKILL_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -L)"

case "$(uname -m)" in
  x86_64|amd64) HOST_ARCH=amd64; OTHER_ARCH=arm64 ;;
  aarch64|arm64) HOST_ARCH=arm64; OTHER_ARCH=amd64 ;;
  *) fail "不支持的处理器架构：$(uname -m)" ;;
esac

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v busybox >/dev/null 2>&1; then
    busybox sha256sum "$1" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  else
    fail "校验需要 sha256sum、BusyBox 或 openssl"
  fi
}

verify_manifest() {
  manifest="$1"
  root="$2"
  arch="$3"
  [ -f "$manifest" ] || return 1
  count=0
  while read -r expected relative extra || [ -n "${expected:-}" ]; do
    [ -n "${expected:-}" ] || continue
    [ -z "${extra:-}" ] || return 1
    case "$expected" in *[!0-9a-fA-F]*|'') return 1 ;; esac
    [ "${#expected}" -eq 64 ] || return 1
    case "$relative" in
      /*|..|../*|*/../*|*/..|*//*) return 1 ;;
      */"$arch"/*) ;;
      *) return 1 ;;
    esac
    file="$root/$relative"
    [ ! -L "$file" ] && [ -f "$file" ] && [ -x "$file" ] || return 1
    actual="$(hash_file "$file")" || return 1
    [ "$actual" = "$expected" ] || return 1
    count=$((count + 1))
  done < "$manifest"
  [ "$count" -gt 0 ]
}

require_manifest() {
  verify_manifest "$1" "$2" "$3" || fail "校验清单验证失败：$1"
}

verify_docs() {
  manifest="$SKILL_DIR/DOCS.sha256"
  [ -f "$manifest" ] || fail "缺少文档校验清单：$manifest"
  while read -r expected relative extra || [ -n "${expected:-}" ]; do
    [ -n "${expected:-}" ] || continue
    [ -z "${extra:-}" ] || fail "文档清单格式无效：$manifest"
    case "$relative" in /*|..|../*|*/../*|*/..) fail "文档清单路径无效：$relative" ;; esac
    case "$expected" in *[!0-9a-fA-F]*|'') fail "文档 SHA256 格式无效：$relative" ;; esac
    [ "${#expected}" -eq 64 ] || fail "文档 SHA256 长度无效：$relative"
    file="$SKILL_DIR/$relative"
    [ ! -L "$file" ] && [ -f "$file" ] || fail "文档缺失：$relative"
    actual="$(hash_file "$file")"
    [ "$actual" = "$expected" ] || fail "文档 SHA256 不匹配：$relative"
  done < "$manifest"
}

create_temp_dir() {
  prefix="$1"
  attempt=0
  candidate="$prefix.$$"
  while ! (umask 077 && mkdir "$candidate") 2>/dev/null; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 10 ] || fail "无法创建暂存目录：$prefix"
    candidate="$prefix.$$.$attempt"
  done
  printf '%s\n' "$candidate"
}

download_file() {
  url="$1"
  output="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 2 -o "$output" "$url" || fail "无法下载当前架构工具"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$output" "$url" || fail "无法下载当前架构工具"
  elif command -v uclient-fetch >/dev/null 2>&1; then
    uclient-fetch -O "$output" "$url" || fail "uclient-fetch 无法下载当前架构工具"
  else
    fail "需要 curl、wget 或 uclient-fetch 下载当前架构工具"
  fi
}

prune_other_arch() {
  root="$1"
  for tool_dir in "$root"/*; do
    [ -f "$tool_dir/USAGE.md" ] || continue
    other_dir="$tool_dir/$OTHER_ARCH"
    [ ! -L "$other_dir" ] || fail "拒绝删除符号链接目录：$other_dir"
    [ ! -e "$other_dir" ] || rm -rf "$other_dir"
  done
}

verify_docs
if [ -f "$SKILL_DIR/RUNTIME_SOURCE_COMMIT" ]; then
  IFS= read -r SOURCE_COMMIT < "$SKILL_DIR/RUNTIME_SOURCE_COMMIT"
  case "$SOURCE_COMMIT" in *[!0-9a-fA-F]*|'') fail "RUNTIME_SOURCE_COMMIT 格式无效" ;; esac
  [ "${#SOURCE_COMMIT}" -eq 40 ] || fail "RUNTIME_SOURCE_COMMIT 必须是 40 位 Git commit"
  RUNTIME_HOME="${TEABLE_SKILLS_RUNTIME_HOME:-$HOME/workspace/.cache/otaku-skills-runtime}"
  case "$RUNTIME_HOME" in /*) ;; *) fail "TEABLE_SKILLS_RUNTIME_HOME 必须是绝对路径" ;; esac
  RUNTIME_DIR="$RUNTIME_HOME/ish-toolbox/$SOURCE_COMMIT"
  PAYLOAD_ROOT="$RUNTIME_DIR/tools"
  MARKER="$RUNTIME_DIR/.ish-toolbox-runtime-managed"
  RUNTIME_VALID=0

  if [ -L "$RUNTIME_DIR" ]; then
    fail "拒绝使用符号链接运行时目录：$RUNTIME_DIR"
  elif [ -d "$RUNTIME_DIR" ] && [ -f "$MARKER" ]; then
    IFS=' ' read -r installed_commit installed_arch extra < "$MARKER" || true
    [ "$installed_commit" = "$SOURCE_COMMIT" ] && [ -z "${extra:-}" ] \
      || fail "运行时目录标记与目标版本不一致：$RUNTIME_DIR"
    case "${installed_arch:-}" in ''|amd64|arm64) ;; *) fail "运行时架构标记无效：$MARKER" ;; esac
    if [ "${installed_arch:-}" = "$HOST_ARCH" ] \
      && verify_manifest "$SKILL_DIR/SHA256SUMS.$HOST_ARCH" "$PAYLOAD_ROOT" "$HOST_ARCH"; then
      RUNTIME_VALID=1
    else
      rm -rf "$RUNTIME_DIR" || fail "无法清理不完整或异架构运行时目录"
    fi
  elif [ -e "$RUNTIME_DIR" ]; then
    fail "拒绝覆盖没有工具箱管理标记的运行时目录：$RUNTIME_DIR"
  fi

  if [ "$RUNTIME_VALID" -eq 0 ]; then
    mkdir -p "$PAYLOAD_ROOT" || fail "无法创建运行时目录：$RUNTIME_DIR"
    printf '%s %s\n' "$SOURCE_COMMIT" "$HOST_ARCH" > "$MARKER"
    manifest="$SKILL_DIR/SHA256SUMS.$HOST_ARCH"
    [ -f "$manifest" ] || fail "缺少当前架构清单：$manifest"
    while read -r expected relative extra || [ -n "${expected:-}" ]; do
      [ -n "${expected:-}" ] || continue
      [ -z "${extra:-}" ] || fail "校验清单格式无效：$manifest"
      case "$expected" in *[!0-9a-fA-F]*|'') fail "SHA256 格式无效：$relative" ;; esac
      [ "${#expected}" -eq 64 ] || fail "SHA256 长度无效：$relative"
      case "$relative" in
        /*|..|../*|*/../*|*/..|*//*) fail "校验清单路径无效：$relative" ;;
        */"$HOST_ARCH"/*) ;;
        *) fail "清单中包含非当前架构条目：$relative" ;;
      esac
      output="$PAYLOAD_ROOT/$relative"
      mkdir -p "$(dirname -- "$output")" || fail "无法创建工具目录：$output"
      download_file "$RAW_BASE/$SOURCE_COMMIT/tools/$relative" "$output"
      chmod +x "$output" || fail "无法设置执行权限：$relative"
      actual="$(hash_file "$output")"
      [ "$actual" = "$expected" ] || fail "SHA256 不匹配：$relative"
    done < "$manifest"
    require_manifest "$manifest" "$PAYLOAD_ROOT" "$HOST_ARCH"
  fi
  prune_other_arch "$PAYLOAD_ROOT"
else
  PAYLOAD_ROOT="$SKILL_DIR"
  require_manifest "$SKILL_DIR/SHA256SUMS.$HOST_ARCH" "$PAYLOAD_ROOT" "$HOST_ARCH"
  prune_other_arch "$PAYLOAD_ROOT"
fi

TOOL_COUNT=0
for tool_dir in "$SKILL_DIR"/*; do
  [ -d "$tool_dir" ] || continue
  tool="${tool_dir##*/}"
  case "$tool" in bin|scripts|references) continue ;; esac
  [ -f "$tool_dir/USAGE.md" ] || fail "$tool 缺少 USAGE.md"
  binary="$PAYLOAD_ROOT/$tool/$HOST_ARCH/$tool"
  [ -f "$binary" ] && [ -x "$binary" ] || fail "$tool 缺少可执行的 $HOST_ARCH 二进制"
  TOOL_COUNT=$((TOOL_COUNT + 1))
done
[ "$TOOL_COUNT" -gt 0 ] || fail "技能目录中没有工具"

case "$PAYLOAD_ROOT" in *:*) fail "工具目录包含 PATH 分隔符 ':'" ;; esac
TMP="$(create_temp_dir "${TMPDIR:-/tmp}/ish-toolbox-update")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM


shell_quote() {
  escaped="$(printf '%s' "$1" | sed "s/'/'\\\\''/g")" || fail "无法转义 PATH"
  printf "'%s'" "$escaped"
}

add_path_block() {
  profile="$1"
  mkdir -p "$(dirname -- "$profile")" || fail "无法创建 shell 配置目录：$profile"
  profile_stage="$TMP/profile"
  if [ -f "$profile" ]; then
    awk '
      /^# BEGIN ish-toolbox PATH$/ { if (inside) exit 2; inside=1; next }
      /^# END ish-toolbox PATH$/ { if (!inside) exit 2; inside=0; next }
      !inside { print }
      END { if (inside) exit 2 }
    ' "$profile" > "$profile_stage" || fail "shell 配置中的工具箱 PATH 区块不完整：$profile"
  else
    : > "$profile_stage"
  fi
  quoted_root="$(shell_quote "$PAYLOAD_ROOT")"
  {
    printf '# BEGIN ish-toolbox PATH\n'
    printf '_ISH_TOOLBOX_ROOT=%s\n' "$quoted_root"
    printf 'case "$(uname -m)" in\n'
    printf '  x86_64|amd64) _ISH_TOOLBOX_ARCH=amd64; _ISH_TOOLBOX_OTHER=arm64 ;;\n'
    printf '  aarch64|arm64) _ISH_TOOLBOX_ARCH=arm64; _ISH_TOOLBOX_OTHER=amd64 ;;\n'
    printf '  *) _ISH_TOOLBOX_ARCH=; _ISH_TOOLBOX_OTHER= ;;\n'
    printf 'esac\n'
    printf 'if [ -n "$_ISH_TOOLBOX_ARCH" ]; then\n'
    printf '  for _ISH_TOOLBOX_TOOL in "$_ISH_TOOLBOX_ROOT"/*; do\n'
    printf '    [ -f "$_ISH_TOOLBOX_TOOL/USAGE.md" ] || continue\n'
    printf '    _ISH_TOOLBOX_STALE_DIR="$_ISH_TOOLBOX_TOOL/$_ISH_TOOLBOX_OTHER"\n'
    printf '    if [ ! -L "$_ISH_TOOLBOX_STALE_DIR" ] && [ -e "$_ISH_TOOLBOX_STALE_DIR" ]; then\n'
    printf '      rm -rf "$_ISH_TOOLBOX_STALE_DIR" >/dev/null 2>&1 || :\n'
    printf '    fi\n'
    printf '    _ISH_TOOLBOX_DIR="$_ISH_TOOLBOX_TOOL/$_ISH_TOOLBOX_ARCH"\n'
    printf '    [ -d "$_ISH_TOOLBOX_DIR" ] || continue\n'
    printf '    case ":${PATH:-}:" in *:"$_ISH_TOOLBOX_DIR":*) ;; *) PATH="$_ISH_TOOLBOX_DIR:${PATH:-}" ;; esac\n'
    printf '  done\n'
    printf 'fi\nexport PATH\nunset _ISH_TOOLBOX_ROOT _ISH_TOOLBOX_ARCH _ISH_TOOLBOX_OTHER _ISH_TOOLBOX_DIR _ISH_TOOLBOX_TOOL _ISH_TOOLBOX_STALE_DIR\n'
    printf '# END ish-toolbox PATH\n'
  } >> "$profile_stage"
  cat "$profile_stage" > "$profile" || fail "无法更新 shell 配置：$profile"
}

add_path_block "$HOME/.profile"
add_path_block "$HOME/.ashrc"
add_path_block "$HOME/.bashrc"
add_path_block "$HOME/.bash_profile"
add_path_block "$HOME/.zshrc"

printf '校验并注册了 %s 个工具，架构：%s，二进制位置：%s\n' "$TOOL_COUNT" "$HOST_ARCH" "$PAYLOAD_ROOT"
printf 'PATH 已动态配置；更新技能包后再次运行 scripts/install.sh 以清除重新带入的异架构文件。\n'
