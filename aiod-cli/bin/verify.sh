#!/bin/sh
set -u

TOOL="aiod-cli"
DIR="$(cd "$(dirname "$0")" && pwd)"
BASE="${AIOD_CLI_RELEASE_BASE:-https://github.com/otaku-say/sandbox-cli/releases/download/latest}"
[ -z "${ISH_TOOLBOX_BIN:-}" ] || PATH="$ISH_TOOLBOX_BIN:$PATH"
export PATH
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 2; }
AWK_BIN="$(command -v gawk || command -v awk)" || { echo "gawk or awk is required" >&2; exit 2; }
if command -v openssl >/dev/null 2>&1; then
  HASH_MODE=openssl
elif command -v sha256sum >/dev/null 2>&1; then
  HASH_MODE=sha256sum
else
  echo "openssl or sha256sum is required for integrity checks" >&2
  exit 2
fi
hash_file() {
  if [ "$HASH_MODE" = openssl ]; then
    openssl dgst -sha256 "$1" | "$AWK_BIN" '{print $NF}'
  else
    sha256sum "$1" | "$AWK_BIN" '{print $1}'
  fi
}

HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  aarch64|arm64) HOST_ARCH=aarch64 ;;
  x86_64|amd64) HOST_ARCH=x86_64 ;;
  *) echo "Cannot verify unsupported host architecture: $HOST_ARCH" >&2; exit 2 ;;
esac
TMP="${TMPDIR:-/tmp}/$TOOL-verify.$$.SHA256SUMS"
[ ! -e "$TMP" ] || { echo "Temporary path already exists; refusing to overwrite" >&2; exit 2; }
cleanup() { rm -f "$TMP"; }
trap cleanup 0
trap 'exit 1' HUP INT TERM
curl -q -fsSL --max-time 20 -o "$TMP" "$BASE/SHA256SUMS" 2>/dev/null || {
  echo "Unable to retrieve the upstream checksum manifest; version is unknown." >&2
  exit 2
}

STATUS=0
for ARCH in aarch64 x86_64; do
  ASSET="$TOOL-$ARCH-linux-musl"
  EXPECTED="$("$AWK_BIN" -v f="$ASSET" '$2 == f { print $1; exit }' "$TMP")"
  TARGET="$DIR/$ASSET"
  if [ -z "$EXPECTED" ] || [ ! -f "$TARGET" ]; then
    if [ "$ARCH" = "$HOST_ARCH" ]; then
      echo "$ARCH: required executable or upstream checksum is missing"
      STATUS=1
    else
      echo "$ARCH: optional non-host executable or checksum is missing"
    fi
    continue
  fi
  ACTUAL="$(hash_file "$TARGET")"
  if [ "$ACTUAL" = "$EXPECTED" ]; then
    echo "$ARCH: current"
  elif [ "$ARCH" = "$HOST_ARCH" ]; then
    echo "$ARCH: stale; run sh $DIR/update.sh"
    STATUS=1
  else
    echo "$ARCH: stale non-host build"
  fi
done
exit "$STATUS"
