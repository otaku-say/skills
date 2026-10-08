#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -L)"
SKILL_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -L)"
sh "$SKILL_DIR/bin/update.sh" "$@"
sh "$SCRIPT_DIR/install.sh"
