#!/bin/sh
set -u

TOOL="aiod-cli"
DIR="$(cd "$(dirname "$0")" && pwd)"
BASE="${AIOD_CLI_RELEASE_BASE:-https://github.com/otaku-say/sandbox-cli/releases/download/latest}"
[ -z "${ISH_TOOLBOX_BIN:-}" ] || PATH="$ISH_TOOLBOX_BIN:$PATH"
export PATH
command -v curl >/dev/null 2>&1 || { echo "需要 curl" >&2; exit 2; }
AWK_BIN="$(command -v gawk || command -v awk)" || { echo "需要 gawk 或 awk" >&2; exit 2; }
if command -v openssl >/dev/null 2>&1; then
  HASH_MODE=openssl
elif command -v sha256sum >/dev/null 2>&1; then
  HASH_MODE=sha256sum
else
  echo "完整性校验需要 openssl 或 sha256sum" >&2
  exit 2
fi
hash_file() {
  if [ "$HASH_MODE" = openssl ]; then
    openssl dgst -sha256 "$1" | "$AWK_BIN" '{print $NF}'
  else
    sha256sum "$1" | "$AWK_BIN" '{print $1}'
  fi
}

case "$(uname -m)" in
  aarch64|arm64) HOST_RELEASE_ARCH=aarch64 ;;
  x86_64|amd64) HOST_RELEASE_ARCH=x86_64 ;;
  *) echo "无法校验不支持的处理器架构：$(uname -m)" >&2; exit 2 ;;
esac
TMP="${TMPDIR:-/tmp}/$TOOL-verify.$$.SHA256SUMS"
[ ! -e "$TMP" ] || { echo "临时路径已存在，拒绝覆盖" >&2; exit 2; }
cleanup() { rm -f "$TMP"; }
trap cleanup 0
trap 'exit 1' HUP INT TERM
curl -q -fsSL --max-time 20 -o "$TMP" "$BASE/SHA256SUMS" 2>/dev/null || {
  echo "无法获取上游校验清单；版本状态未知。" >&2
  exit 2
}

STATUS=0
for ARCH in aarch64 x86_64; do
  ASSET="$TOOL-$ARCH-linux-musl"
  case "$ARCH" in aarch64) TARGET_ARCH=arm64 ;; x86_64) TARGET_ARCH=amd64 ;; esac
  EXPECTED="$("$AWK_BIN" -v f="$ASSET" '$2 == f { print $1; exit }' "$TMP")"
  TARGET="$DIR/$TARGET_ARCH/$TOOL"
  if [ -z "$EXPECTED" ] || [ ! -f "$TARGET" ]; then
    echo "$TARGET_ARCH：缺少二进制文件或上游校验值"
    STATUS=1
    continue
  fi
  ACTUAL="$(hash_file "$TARGET")"
  if [ "$ACTUAL" = "$EXPECTED" ]; then
    echo "$TARGET_ARCH：校验通过"
  else
    echo "$TARGET_ARCH：版本过旧，请运行 sh $DIR/update.sh"
    STATUS=1
  fi
done
exit "$STATUS"
