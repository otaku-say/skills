#!/bin/sh
set -eu
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -L)"
sh "$SCRIPT_DIR/verify.sh"
printf '本技能没有独立运行时资源；技能文件请通过对应的 Skills 管理器更新。\n'
printf '更新技能文件后运行 scripts/install.sh 完成安装后处理。\n'
