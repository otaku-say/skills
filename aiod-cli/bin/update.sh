#!/bin/sh
set -u

TOOL="aiod-cli"
DIR="$(cd "$(dirname "$0")" && pwd)"
BASE="${AIOD_CLI_RELEASE_BASE:-https://github.com/otaku-say/sandbox-cli/releases/download/latest}"
[ -z "${ISH_TOOLBOX_BIN:-}" ] || PATH="$ISH_TOOLBOX_BIN:$PATH"
export PATH
FORCE=0
case "${1:-}" in
  "") ;;
  --force) FORCE=1 ;;
  *) echo "Usage: sh $0 [--force]" >&2; exit 2 ;;
esac

fail() { echo "Update failed: $1" >&2; exit "${2:-1}"; }
command -v curl >/dev/null 2>&1 || fail "curl is required" 1
AWK_BIN="$(command -v gawk || command -v awk)" || fail "gawk or awk is required" 1
if command -v openssl >/dev/null 2>&1; then
  HASH_MODE=openssl
elif command -v sha256sum >/dev/null 2>&1; then
  HASH_MODE=sha256sum
else
  fail "openssl or sha256sum is required for integrity checks" 1
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
  *) fail "unsupported host architecture: $HOST_ARCH" 1 ;;
esac
TMP="${TMPDIR:-/tmp}/$TOOL-update.$$"
(umask 077 && mkdir "$TMP") || fail "cannot create a unique temporary directory" 1
cleanup() { rm -rf "$TMP"; }
trap cleanup 0
trap 'exit 1' HUP INT TERM
curl -q -fsSL --retry 2 --retry-delay 2 -o "$TMP/SHA256SUMS" "$BASE/SHA256SUMS" || fail "cannot download checksum manifest" 1

for ARCH in aarch64 x86_64; do
  ASSET="$TOOL-$ARCH-linux-musl"
  EXPECTED="$("$AWK_BIN" -v f="$ASSET" '$2 == f { print $1; exit }' "$TMP/SHA256SUMS")"
  TARGET="$DIR/$ASSET"
  if [ -z "$EXPECTED" ]; then
    echo "Warning: upstream release has no $ASSET asset"
    [ "$ARCH" != "$HOST_ARCH" ] || fail "required host asset is missing" 1
    continue
  fi
  if [ -f "$TARGET" ] && [ "$FORCE" -eq 0 ]; then
    CURRENT="$(hash_file "$TARGET")"
    if [ "$CURRENT" = "$EXPECTED" ]; then
      echo "$ARCH: already current"
      continue
    fi
  fi
  curl -q -fsSL --retry 2 --retry-delay 2 -o "$TMP/$ASSET" "$BASE/$ASSET" || {
    [ "$ARCH" != "$HOST_ARCH" ] || fail "download failed for required host asset" 1
    echo "Warning: download failed for optional $ARCH asset"
    continue
  }
  ACTUAL="$(hash_file "$TMP/$ASSET")"
  [ "$ACTUAL" = "$EXPECTED" ] || {
    [ "$ARCH" != "$HOST_ARCH" ] || fail "checksum mismatch for required host asset" 1
    echo "Warning: checksum mismatch for optional $ARCH asset"
    continue
  }
  chmod +x "$TMP/$ASSET" 2>/dev/null || true
  mv "$TMP/$ASSET" "$TARGET" || {
    [ "$ARCH" != "$HOST_ARCH" ] || fail "cannot replace required host asset" 1
    echo "Warning: cannot replace optional $ARCH asset"
    continue
  }
  echo "$ARCH: updated"
done

"$AWK_BIN" -v prefix="$TOOL-" '$2 ~ "^" prefix { print }' "$TMP/SHA256SUMS" > "$TMP/local.SHA256SUMS" || fail "cannot prepare checksum manifest" 1
mv "$TMP/local.SHA256SUMS" "$DIR/SHA256SUMS" || fail "cannot save checksum manifest" 1
chmod +x "$DIR/$TOOL-$HOST_ARCH-linux-musl" 2>/dev/null || true
VERSION="$("$DIR/$TOOL-$HOST_ARCH-linux-musl" version)" || fail "updated host binary could not run" 1
printf '%s\n' "$VERSION" | "$AWK_BIN" 'NR == 1 { print; exit }'
echo "Run sh $DIR/verify.sh to verify both architecture builds."
