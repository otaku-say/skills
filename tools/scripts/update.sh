#!/bin/sh
set -eu

RAW_BASE="${ISH_TOOLBOX_RAW_BASE:-https://raw.githubusercontent.com/otaku-say/skills}"

fail() {
  printf '更新失败：%s\n' "$1" >&2
  exit 1
}

usage() {
  printf '用法：sh %s [选项]\n\n' "$0"
  printf '  （无选项）                 校验并注册工具箱 PATH（默认行为）\n'
  printf '  --set-default-busybox      校验注册后，将工具箱 busybox 设为默认终端：\n'
  printf '                             系统自带 busybox 先备份（<路径>.pre-toolbox）再原地替换；\n'
  printf '                             busybox 系（Alpine/iSH）：替换 /bin/busybox 即刻全面生效；\n'
  printf '                             其他发行版：另在目标目录（默认 /usr/local/bin）建立 applet 链接\n'
  printf '  --unset-default-busybox    还原系统原版 busybox / 移除 applet 链接\n'
  printf '  --busybox-links-dir=DIR    links 模式目标目录，须为绝对路径（默认 /usr/local/bin）\n'
  printf '  --help                     显示本帮助\n'
}

SET_DEFAULT_BUSYBOX=0
UNSET_DEFAULT_BUSYBOX=0
BUSYBOX_LINKS_DIR=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --set-default-busybox) SET_DEFAULT_BUSYBOX=1 ;;
    --unset-default-busybox) UNSET_DEFAULT_BUSYBOX=1 ;;
    --busybox-links-dir=*) BUSYBOX_LINKS_DIR="${1#--busybox-links-dir=}" ;;
    --help|-h) usage; exit 0 ;;
    *) fail "未知参数：$1（--help 查看用法）" ;;
  esac
  shift
done
if [ "$SET_DEFAULT_BUSYBOX" -eq 1 ] && [ "$UNSET_DEFAULT_BUSYBOX" -eq 1 ]; then
  fail "不能同时使用 --set-default-busybox 与 --unset-default-busybox"
fi
if [ -n "$BUSYBOX_LINKS_DIR" ]; then
  case "$BUSYBOX_LINKS_DIR" in /*) ;; *) fail "--busybox-links-dir 必须是绝对路径" ;; esac
fi
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

default_busybox_mode() {
  case "${ISH_TOOLBOX_BUSYBOX_MODE:-}" in
    replace|links) printf '%s\n' "$ISH_TOOLBOX_BUSYBOX_MODE"; return 0 ;;
    '') ;;
    *) fail "ISH_TOOLBOX_BUSYBOX_MODE 仅支持 replace|links" ;;
  esac
  if [ -f /etc/alpine-release ] \
    || { [ -L /bin/sh ] && { [ "$(readlink /bin/sh)" = "/bin/busybox" ] || [ "$(readlink /bin/sh)" = "busybox" ]; }; }; then
    printf 'replace\n'
  else
    printf 'links\n'
  fi
}

unset_default_busybox() {
  handled=0
  for f in /bin/busybox /usr/bin/busybox /sbin/busybox /usr/sbin/busybox; do
    BAK="$f.pre-toolbox"
    if [ ! -f "$BAK" ]; then continue; fi
    if [ -L "$BAK" ]; then continue; fi
    "$BAK" sh -c 'exit 0' >/dev/null 2>&1 || fail "备份文件无法运行，拒绝还原：$BAK"
    # 幂等护栏：当前已是系统原版（与备份一致）时不重复写入
    if [ -f "$f" ] && [ "$(hash_file "$f")" = "$(hash_file "$BAK")" ]; then
      printf '  %s 当前已是系统原版（与备份一致），无需还原\n' "$f"
      handled=1
      continue
    fi
    cp "$BAK" "$f" || fail "无法还原（需要 root 权限）：$f"
    chmod 755 "$f"
    command -v restorecon >/dev/null 2>&1 && restorecon "$f" 2>/dev/null || true
    handled=1
    printf '已还原系统原版 busybox：%s（来源：%s）\n' "$f" "$BAK"
  done
  LINKS_DIR="${BUSYBOX_LINKS_DIR:-/usr/local/bin}"
  if [ -d "$LINKS_DIR" ]; then
    removed=0
    for f in "$LINKS_DIR"/*; do
      if [ "${f##*/}" = busybox ]; then continue; fi
      if [ -L "$f" ]; then
        case "$(readlink "$f")" in
          */busybox/"$HOST_ARCH"/busybox)
            if rm -f "$f"; then removed=$((removed + 1)); fi ;;
        esac
      fi
    done
    if [ "$removed" -gt 0 ]; then
      handled=1
      printf '已移除 %s 个工具箱 busybox applet 链接（%s）\n' "$removed" "$LINKS_DIR"
    fi
  fi
  if [ "$handled" -eq 0 ]; then
    printf '未发现工具箱 busybox 的默认化痕迹（检查了 /bin、/usr/bin、/sbin、/usr/sbin 的 .pre-toolbox 与 %s）\n' "$LINKS_DIR"
  fi
}

if [ "$UNSET_DEFAULT_BUSYBOX" -eq 1 ]; then
  unset_default_busybox
  exit 0
fi

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
  if command -v wget >/dev/null 2>&1; then
    if wget -q -O "$output" "$url"; then return 0; fi
    printf 'wget 下载失败，尝试 curl 回退\n' >&2
  fi
  if command -v curl >/dev/null 2>&1; then
    if curl -q -fsSL --retry 2 --retry-delay 2 -o "$output" "$url"; then return 0; fi
    printf 'curl 下载失败，尝试 uclient-fetch 回退\n' >&2
  fi
  if command -v uclient-fetch >/dev/null 2>&1; then
    if uclient-fetch -O "$output" "$url"; then return 0; fi
  fi
  fail "无法下载当前架构工具"
}

prune_other_arch() {
  root="$1"
  for tool_dir in "$root"/*; do
    [ -d "$tool_dir" ] || continue
    [ -f "$tool_dir/USAGE.md" ] || [ -d "$tool_dir/$HOST_ARCH" ] || continue
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
    printf '    [ -d "$_ISH_TOOLBOX_TOOL" ] || continue\n'
    printf '    _ISH_TOOLBOX_NAME="${_ISH_TOOLBOX_TOOL##*/}"\n'
    printf '    _ISH_TOOLBOX_DIR="$_ISH_TOOLBOX_TOOL/$_ISH_TOOLBOX_ARCH"\n'
    printf '    [ -x "$_ISH_TOOLBOX_DIR/$_ISH_TOOLBOX_NAME" ] || continue\n'
    printf '    _ISH_TOOLBOX_STALE_DIR="$_ISH_TOOLBOX_TOOL/$_ISH_TOOLBOX_OTHER"\n'
    printf '    if [ ! -L "$_ISH_TOOLBOX_STALE_DIR" ] && [ -e "$_ISH_TOOLBOX_STALE_DIR" ]; then\n'
    printf '      rm -rf "$_ISH_TOOLBOX_STALE_DIR" >/dev/null 2>&1 || :\n'
    printf '    fi\n'
    printf '    case ":${PATH:-}:" in *:"$_ISH_TOOLBOX_DIR":*) ;; *) PATH="$_ISH_TOOLBOX_DIR:${PATH:-}" ;; esac\n'
    printf '  done\n'
    printf 'fi\nexport PATH\nunset _ISH_TOOLBOX_ROOT _ISH_TOOLBOX_ARCH _ISH_TOOLBOX_OTHER _ISH_TOOLBOX_DIR _ISH_TOOLBOX_NAME _ISH_TOOLBOX_TOOL _ISH_TOOLBOX_STALE_DIR\n'
    printf '# END ish-toolbox PATH\n'
  } >> "$profile_stage"
  cat "$profile_stage" > "$profile" || fail "无法更新 shell 配置：$profile"
}

add_path_block "$HOME/.profile"
add_path_block "$HOME/.ashrc"
add_path_block "$HOME/.bashrc"
add_path_block "$HOME/.bash_profile"
add_path_block "$HOME/.zshrc"

# 替换系统自带 busybox（发现即处理；usrmerge 下多路径自动去重）：备份 + 原地替换 + 自检 + 失败回滚
replace_system_busybox() {
  BIN_SHA="$(hash_file "$BIN")"
  SYS_BB_FOUND=0
  SEEN=""
  for f in /bin/busybox /usr/bin/busybox /sbin/busybox /usr/sbin/busybox; do
    [ -e "$f" ] || continue
    if [ -L "$f" ] && [ ! -e "$f" ]; then printf '  跳过失效符号链接：%s\n' "$f"; continue; fi
    r="$(readlink -f "$f" 2>/dev/null || true)"
    if [ -z "$r" ]; then r="$f"; fi
    if [ -L "$f" ]; then printf '  符号链接 %s -> %s\n' "$f" "$r"; fi
    case " $SEEN " in *" $r "*) continue ;; esac
    SEEN="$SEEN $r"
    [ -f "$r" ] || continue
    desc="$("$r" 2>&1 | head -n 1 || true)"
    case "$desc" in
      *BusyBox*|*busybox*) ;;
      *) printf '  跳过非 busybox 文件：%s\n' "$r"; continue ;;
    esac
    SYS_BB_FOUND=$((SYS_BB_FOUND + 1))
    if [ "$(hash_file "$r")" = "$BIN_SHA" ]; then
      printf '  已是工具箱版本：%s\n' "$r"
      continue
    fi
    BAK="$r.pre-toolbox"
    if [ -f "$BAK" ] && [ ! -L "$BAK" ]; then
      if [ "$(hash_file "$BAK")" = "$BIN_SHA" ]; then
        cp "$r" "$BAK" && chmod 755 "$BAK" \
          && printf '  备份内容为工具箱版本，已重新备份系统原版：%s\n' "$BAK"
      fi
    else
      cp "$r" "$BAK" || fail "无法备份系统 busybox（需要 root 权限）：$BAK"
      chmod 755 "$BAK"
      printf '  系统原版已备份：%s\n' "$BAK"
    fi
    cp "$BIN" "$r" || fail "无法替换（需要 root 权限）：$r"
    chmod 755 "$r"
    command -v restorecon >/dev/null 2>&1 && restorecon "$r" 2>/dev/null || true
    if ! "$r" sh -c 'exit 0' >/dev/null 2>&1; then
      cp "$BAK" "$r" >/dev/null 2>&1 || printf '警告：回滚失败，请手动恢复：cp %s %s\n' "$BAK" "$r" >&2
      chmod 755 "$r" 2>/dev/null || :
      fail "替换后自检失败，已尝试回滚：$r"
    fi
    printf '  ✓ 已替换系统自带 busybox：%s\n' "$r"
  done
  if [ "$SYS_BB_FOUND" -eq 0 ]; then
    printf '  未发现系统自带 busybox（跳过替换步骤）\n'
  fi
}

set_default_busybox() {
  BIN="$PAYLOAD_ROOT/busybox/$HOST_ARCH/busybox"
  [ -f "$BIN" ] && [ -x "$BIN" ] || fail "工具箱缺少 $HOST_ARCH 版 busybox：$BIN"
  "$BIN" sh -c 'exit 0' >/dev/null 2>&1 || fail "工具箱 busybox 无法在本机运行（架构或内核不兼容）：$BIN"
  BB_DESC="$("$BIN" 2>/dev/null | head -n 1)"
  [ -n "$BB_DESC" ] || BB_DESC="工具箱 busybox"

  mode="$(default_busybox_mode)"

  printf '→ 替换系统自带 busybox（如有；备份后缀 .pre-toolbox）\n'
  replace_system_busybox

  if [ "$mode" = replace ]; then
    [ -f /bin/busybox ] || fail "busybox 系系统却未找到 /bin/busybox，异常"
    [ "$(hash_file /bin/busybox)" = "$(hash_file "$BIN")" ] || fail "/bin/busybox 不是工具箱版本，替换未完成"
    printf '✓ 默认 busybox 已切换为工具箱版本（busybox 系：/bin/sh 与全部 applet 即刻生效）\n'
    printf '  版本：%s\n' "$BB_DESC"
    printf '  系统原版备份：/bin/busybox.pre-toolbox\n'
    printf '  还原命令：sh %s --unset-default-busybox\n' "$0"
    return 0
  fi
  LINKS_DIR="${BUSYBOX_LINKS_DIR:-/usr/local/bin}"
  if [ ! -d "$LINKS_DIR" ]; then
    mkdir -p "$LINKS_DIR" || fail "无法创建目录：$LINKS_DIR（需要 root 权限）"
  fi
  [ -w "$LINKS_DIR" ] || fail "目录不可写：$LINKS_DIR（请用 root/sudo 运行，或用 --busybox-links-dir 指定其他目录）"
  "$BIN" --list > "$TMP/busybox-applets" 2>/dev/null || fail "无法获取 busybox applet 列表"
  created=0; updated=0; skipped=0; conflicts=0; conflict_list=""
  while IFS= read -r applet || [ -n "$applet" ]; do
    if [ -z "$applet" ]; then continue; fi
    if [ "$applet" = busybox ]; then continue; fi
    dest="$LINKS_DIR/$applet"
    if [ -L "$dest" ]; then
      target="$(readlink "$dest")"
      if [ "$target" = "$BIN" ]; then
        skipped=$((skipped + 1))
        continue
      fi
      case "$target" in
        */busybox/"$HOST_ARCH"/busybox)
          ln -sfn "$BIN" "$dest" || fail "无法更新链接：$dest"
          updated=$((updated + 1))
          continue ;;
      esac
      conflicts=$((conflicts + 1))
      conflict_list="$conflict_list $applet"
      continue
    fi
    if [ -e "$dest" ]; then
      conflicts=$((conflicts + 1))
      conflict_list="$conflict_list $applet"
      continue
    fi
    ln -s "$BIN" "$dest" || fail "无法创建链接：$dest"
    created=$((created + 1))
  done < "$TMP/busybox-applets"
  printf '✓ 工具箱 busybox 已就位（links 步完成）\n'
  printf '  版本：%s\n' "$BB_DESC"
  printf '  目标目录：%s（新建 %s / 更新 %s / 跳过 %s / 冲突 %s）\n' "$LINKS_DIR" "$created" "$updated" "$skipped" "$conflicts"
  if [ "$conflicts" -gt 0 ]; then
    printf '  冲突 applet（保留原文件）：%s\n' "$(printf '%s' "$conflict_list" | cut -c1-160)"
  fi
  if case ":${PATH:-}:" in *":$LINKS_DIR:"*) true ;; *) false ;; esac; then
    printf '  已位于 PATH：%s\n' "$LINKS_DIR"
  else
    printf '  注意：%s 不在当前 PATH 中，请检查 shell 配置\n' "$LINKS_DIR"
  fi
  if [ "$LINKS_DIR" = /usr/local/bin ]; then
    printf '  还原命令：sh %s --unset-default-busybox\n' "$0"
  else
    printf '  还原命令：sh %s --unset-default-busybox --busybox-links-dir=%s\n' "$0" "$LINKS_DIR"
  fi
}

printf '校验并注册了 %s 个工具，架构：%s，二进制位置：%s\n' "$TOOL_COUNT" "$HOST_ARCH" "$PAYLOAD_ROOT"
printf 'PATH 已动态配置；更新技能包后再次运行 scripts/install.sh 以清除重新带入的异架构文件。\n'
printf '如需将工具箱 busybox 设为默认终端，运行：sh %s --set-default-busybox\n' "$0"

if [ "$SET_DEFAULT_BUSYBOX" -eq 1 ]; then
  set_default_busybox
fi
