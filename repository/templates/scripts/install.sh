#!/bin/sh
set -eu
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -L)"
SKILL_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -L)"
sh "$SCRIPT_DIR/verify.sh"
printf '本技能没有独立运行时资源，无需额外安装。\n'
printf '技能目录：%s\n' "$SKILL_DIR"
