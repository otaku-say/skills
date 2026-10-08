#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -L)"
SKILL_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -L)"
if [ -f "$SKILL_DIR/RUNTIME_SOURCE_COMMIT" ]; then
  [ "$#" -eq 0 ] || { printf 'Teable 运行时更新不接受参数。\n' >&2; exit 2; }
  sh "$SCRIPT_DIR/update-runtime.sh"
else
  sh "$SCRIPT_DIR/update-release.sh" "$@"
fi
sh "$SCRIPT_DIR/install.sh"
