#!/bin/sh
set -eu

DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
case "$(uname -m)" in
  x86_64|amd64|aarch64|arm64) ;;
  *) printf '不支持的处理器架构：%s\n' "$(uname -m)" >&2; exit 1 ;;
esac
exec sh "$DIR/update.sh" "$@"
