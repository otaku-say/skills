#!/bin/sh
set -eu

REPOSITORY="https://github.com/otaku-say/skills.git"
PREFIX="${HOME:?请先设置 HOME}/.local/share/ish-toolbox"
SOURCE_OVERRIDE="${ISH_TOOLBOX_SOURCE_DIR:-}"

fail() {
  printf '更新失败：%s\n' "$1" >&2
  exit 1
}

[ "$#" -eq 0 ] || fail "用法：sh $0"
case "$PREFIX" in
  /*) [ "$PREFIX" != / ] || fail "拒绝使用根目录作为安装位置" ;;
  *) fail "安装目录必须是绝对路径" ;;
esac

mkdir -p "$PREFIX" || fail "无法创建安装目录 $PREFIX"
TMP="$PREFIX/.update.$$"
attempt=0
while ! (umask 077 && mkdir "$TMP") 2>/dev/null; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 10 ] || fail "无法创建临时目录"
  TMP="$PREFIX/.update.$$.$attempt"
done
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT HUP INT TERM

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
  [ -f "$manifest" ] || fail "缺少校验清单：$manifest"
  while read -r expected relative extra || [ -n "${expected:-}" ]; do
    [ -n "${expected:-}" ] || continue
    [ -z "${extra:-}" ] || fail "校验清单格式无效：$manifest"
    case "$relative" in
      /*|..|../*|*/../*|*/..) fail "校验清单路径无效：$relative" ;;
    esac
    file="$root/$relative"
    [ -f "$file" ] || fail "清单中的文件不存在：$relative"
    actual="$(hash_file "$file")"
    [ "$actual" = "$expected" ] || fail "SHA256 不匹配：$relative"
  done < "$manifest"
}

SOURCE="$SOURCE_OVERRIDE"
if [ -n "$SOURCE" ]; then
  [ -d "$SOURCE" ] || fail "本地测试源目录不存在：$SOURCE"
else
  if command -v git >/dev/null 2>&1; then
    if git clone --quiet --depth=1 --filter=blob:none --sparse "$REPOSITORY" "$TMP/repo" >/dev/null 2>&1 \
      && git -C "$TMP/repo" sparse-checkout set tools >/dev/null 2>&1; then
      SOURCE="$TMP/repo/tools"
    fi
  fi
  if [ -z "$SOURCE" ]; then
    command -v tar >/dev/null 2>&1 || fail "需要 git，或安装 tar 与 curl/wget"
    mkdir "$TMP/archive"
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL --retry 2 -o "$TMP/skills.tar.gz" \
        https://codeload.github.com/otaku-say/skills/tar.gz/refs/heads/main \
        || fail "无法下载技能仓库"
    elif command -v wget >/dev/null 2>&1; then
      wget -q -O "$TMP/skills.tar.gz" \
        https://codeload.github.com/otaku-say/skills/tar.gz/refs/heads/main \
        || fail "无法下载技能仓库"
    else
      fail "需要 git，或安装 curl/wget 与 tar"
    fi
    tar -xzf "$TMP/skills.tar.gz" -C "$TMP/archive" --strip-components=1 skills-main/tools \
      || fail "无法解压工具目录"
    SOURCE="$TMP/archive/tools"
  fi
fi

[ -f "$SOURCE/SHA256SUMS.amd64" ] || fail "源目录缺少 amd64 校验清单"
[ -f "$SOURCE/SHA256SUMS.arm64" ] || fail "源目录缺少 arm64 校验清单"
[ -f "$SOURCE/DOCS.sha256" ] || fail "源目录缺少说明文档校验清单"
verify_manifest "$SOURCE/SHA256SUMS.amd64" "$SOURCE"
verify_manifest "$SOURCE/SHA256SUMS.arm64" "$SOURCE"
verify_manifest "$SOURCE/DOCS.sha256" "$SOURCE"

TOOL_COUNT=0
for tool_dir in "$SOURCE"/*; do
  [ -d "$tool_dir" ] || continue
  tool="$(basename "$tool_dir")"
  case "$tool" in scripts|references) continue ;; esac
  [ -f "$tool_dir/USAGE.md" ] || fail "$tool 缺少 USAGE.md"
  for arch in amd64 arm64; do
    binary="$tool_dir/$arch/$tool"
    [ -f "$binary" ] && [ -x "$binary" ] || fail "$tool 缺少可执行的 $arch 二进制"
  done
  TOOL_COUNT=$((TOOL_COUNT + 1))
done
[ "$TOOL_COUNT" -gt 0 ] || fail "源目录中没有工具"

mkdir "$TMP/new-tools" "$TMP/new-bin"
for item in "$SOURCE"/*; do
  item_name="$(basename "$item")"
  case "$item_name" in scripts|references|SKILL.md) continue ;; esac
  cp -R "$item" "$TMP/new-tools/" || fail "无法暂存 $item_name"
done
for tool_dir in "$TMP/new-tools"/*; do
  [ -d "$tool_dir" ] || continue
  tool="$(basename "$tool_dir")"
  case "$tool" in *[!A-Za-z0-9._+-]*) fail "工具名包含不支持的字符：$tool" ;; esac
  cat > "$TMP/new-bin/$tool" <<'WRAPPER'
#!/bin/sh
set -eu
ROOT="${HOME:?请先设置 HOME}/.local/share/ish-toolbox"
TOOL="$(basename -- "$0")"
case "$(uname -m)" in
  x86_64|amd64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) printf '不支持的处理器架构：%s\n' "$(uname -m)" >&2; exit 1 ;;
esac
PROGRAM="$ROOT/tools/$TOOL/$ARCH/$TOOL"
[ -x "$PROGRAM" ] || { printf '找不到工具二进制：%s\n' "$PROGRAM" >&2; exit 127; }
exec "$PROGRAM" "$@"
WRAPPER
  chmod 755 "$TMP/new-bin/$tool"
done

OLD_TOOLS="$TMP/old-tools"
OLD_BIN="$TMP/old-bin"
[ ! -e "$PREFIX/tools" ] || mv "$PREFIX/tools" "$OLD_TOOLS" || fail "无法备份旧工具目录"
[ ! -e "$PREFIX/bin" ] || mv "$PREFIX/bin" "$OLD_BIN" || {
  [ ! -e "$OLD_TOOLS" ] || mv "$OLD_TOOLS" "$PREFIX/tools"
  fail "无法备份旧命令入口目录"
}
if ! mv "$TMP/new-tools" "$PREFIX/tools"; then
  [ ! -e "$OLD_TOOLS" ] || mv "$OLD_TOOLS" "$PREFIX/tools"
  [ ! -e "$OLD_BIN" ] || mv "$OLD_BIN" "$PREFIX/bin"
  fail "无法安装工具目录"
fi
if ! mv "$TMP/new-bin" "$PREFIX/bin"; then
  rm -rf "$PREFIX/tools"
  [ ! -e "$OLD_TOOLS" ] || mv "$OLD_TOOLS" "$PREFIX/tools"
  [ ! -e "$OLD_BIN" ] || mv "$OLD_BIN" "$PREFIX/bin"
  fail "无法安装命令入口"
fi

add_path_block() {
  profile="$1"
  mkdir -p "$(dirname "$profile")"
  if [ -f "$profile" ] && grep -Fq '# BEGIN ish-toolbox PATH' "$profile"; then
    return
  fi
  {
    printf '\n# BEGIN ish-toolbox PATH\n'
    printf 'case ":$PATH:" in *:"$HOME/.local/share/ish-toolbox/bin":*) ;; *) PATH="$HOME/.local/share/ish-toolbox/bin:$PATH" ;; esac\n'
    printf 'export PATH\n# END ish-toolbox PATH\n'
  } >> "$profile" || fail "无法更新 shell 配置：$profile"
}

add_path_block "$HOME/.profile"
add_path_block "$HOME/.bashrc"
add_path_block "$HOME/.bash_profile"
add_path_block "$HOME/.zshrc"

printf '已安装 %s 个工具到 %s\n' "$TOOL_COUNT" "$PREFIX"
printf 'PATH 配置已写入 shell 启动文件；当前会话可运行：export PATH="%s/bin:$PATH"\n' "$PREFIX"
