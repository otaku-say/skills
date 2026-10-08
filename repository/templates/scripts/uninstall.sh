#!/bin/sh
set -eu
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -L)"
sh "$SCRIPT_DIR/verify.sh"
printf '本技能没有由生命周期脚本创建的持久资源。\n'
printf '技能文件由对应的 Skills 管理器卸载。\n'
