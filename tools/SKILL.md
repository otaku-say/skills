---
name: tools
description: >-
  当用户需要在 Linux 沙箱中批量安装、更新、校验或卸载 ish-toolbox 工具集，或查找其中 rg、jaq、python3、ssh、curl 等命令的用法，或把工具箱 BusyBox 设为系统默认终端时，使用此工具箱技能。它是一个统一技能，不会把每个工具目录单独注册为 Agent 技能。
compatibility: >-
  目标发行版包括 Alpine、Debian、OpenCloudOS 和 OpenWrt，支持 Linux amd64/x86_64 与 arm64/aarch64；OpenWrt 仅限这两个架构。二进制为静态单文件；python3 与 uv 为“静态壳 + xz 载荷”的自解压单文件（外壳静态、首次运行解压到 /tmp，之后零开销；Alpine/iSH 直接可用，glibc 系需自备 musl loader）。BusyBox 可设为系统默认终端（Alpine/iSH 替换 /bin/busybox；其他发行版建立 /usr/local/bin applet 链接；随时可 --unset 还原）。amd64 已在 Alpine 与 Ubuntu 环境完成安装、更新与运行测试；arm64 已在 iSH 真机完成安装与运行测试（python3/uv/busybox 全链路）；OpenWrt 未实测。PATH 配置目标为 POSIX shell、BusyBox ash、Bash 和 Zsh。Teable 版运行时下载需要 curl、wget 或 uclient-fetch，并需要 sha256sum、BusyBox sha256sum 或 openssl 之一。
---

# ish-toolbox 工具箱

从仓库同步的一组静态 Linux 命令行工具。一个 `tools` 目录对应一个 Agent 技能；`tools/<工具名>/USAGE.md` 是该工具自己的说明，不需要也不应把每个工具注册成独立技能。

## 安装

从 main 安装完整技能后运行：

```sh
npx skills add otaku-say/skills --skill tools -g
sh /path/to/installed/tools/scripts/install.sh
```

安装脚本从自身位置动态推导技能目录，检测 `uname -m`，验证当前架构的 SHA256 后删除技能目录中另一架构的二进制目录，再将当前架构的各工具目录加入 shell PATH。它不搬移或复制二进制，不写死技能安装位置，也不需要 root。路径配置写入 `.profile`、`.ashrc`、`.bashrc`、`.bash_profile` 和 `.zshrc`；新 shell 或重新加载配置后生效。

main 包含 47 个工具的 amd64 和 arm64 二进制（含自解压壳单文件 `python3`、`uv`）。安装后只保留当前主机架构；Skills 管理器更新技能包时可能重新带入另一架构，因此更新后应运行 `scripts/install.sh`。若遗漏，已有 PATH 启动配置会在下一个 shell 启动时检测并裁剪，不会在每次命令调用时增加 wrapper 开销。

Teable 使用 `teable` 分支的轻量包。该包不含二进制；安装脚本从 `RUNTIME_SOURCE_COMMIT` 指定的 main commit 逐个下载当前架构文件，先校验 SHA256 再保存到 `${TEABLE_SKILLS_RUNTIME_HOME:-$HOME/workspace/.cache/otaku-skills-runtime}/ish-toolbox/`，不写入只读的技能目录。默认位置位于 Teable 持久 workspace 下，跨 sandbox 重建保留；显式设置 `TEABLE_SKILLS_RUNTIME_HOME` 时必须指向持久目录。不会下载或保留另一架构。分支构建及 512000 字节限制见仓库 `repository/branch-profiles/`。

## 更新与验证

更新技能说明或脚本后，运行 Skills 管理器更新，再重新安装以校验并清理异架构文件：

```sh
npx skills update tools -g
sh /path/to/installed/tools/scripts/install.sh
```

更新当前发行分支提供的二进制并同步 PATH：

```sh
sh /path/to/installed/tools/scripts/update.sh
sh /path/to/installed/tools/scripts/verify.sh
```

main 版使用技能包中已校验的当前架构二进制；Teable 版只从固定 main commit 下载当前架构。重复运行安装、更新、验证不会增加 PATH 重复项。校验失败时不会将未校验的运行时路径加入 PATH。

## 将 BusyBox 设为默认终端（推荐）

工具箱自带 BusyBox 1.38.0 静态单文件（408 个 applet，比 Alpine 3.21 与 iSH 系统自带的 1.37 更新）。一条命令即可让它成为系统默认终端（脚本按 `uname -m` 自动选择 arm64/amd64 二进制并自动判定模式）：

```sh
sh /path/to/installed/tools/scripts/install.sh --set-default-busybox
```

- **系统已自带 busybox** 时（`/bin`、`/usr/bin`、`/sbin`、`/usr/sbin` 任一位置）：先备份为 `<路径>.pre-toolbox`，再原地替换为工具箱静态版；不调用包管理器、随时可还原。
- **busybox 系**（Alpine、iSH 等：存在 `/etc/alpine-release`，或 `/bin/sh` 指向 busybox）：替换后系统 applet 与 `/bin/sh` 立即使用工具箱版本；替换失败会自动回滚。
- **其他发行版**（Debian/Ubuntu/CentOS/Fedora/Arch/OpenCloudOS/OpenWrt 等）：另在目标目录（默认 `/usr/local/bin`，需 root 或 sudo）建立全部 applet 软链；已存在的同名文件不会被覆盖（计入“冲突”）。目标目录可用 `--busybox-links-dir=DIR` 指定。

还原系统原状：

```sh
sh /path/to/installed/tools/scripts/install.sh --unset-default-busybox
```

`--set-default-busybox` 会先完成常规校验与 PATH 注册再设定；`--unset-default-busybox` 不依赖校验，可在工具箱损坏时直接还原；自定义目录的还原需带相同的 `--busybox-links-dir`。set 与 unset 均幂等，可重复执行。

### Agent 须知：默认终端就是工具箱 BusyBox

设定后（aio 系列镜像与 iSH 默认已设定），`sh`、`ls`、`grep` 等命令即工具箱版本。**Agent 应主动使用这一默认终端**：

- 在 iSH/Alpine 上：`/bin/sh`（以及对话式命令执行入口）本身就是工具箱 BusyBox，直接执行 `sh -c '...'` 即已使用；`busybox | head -1` 应显示 1.38.0。
- 在其他发行版上：优先路径为 `/usr/local/bin`（先于 /usr/bin、/bin 生效），Agent 以命令名调用即可用到工具箱版本；需要绝对确定时用工具箱内绝对路径 `tools/busybox/<arch>/busybox sh -c '...'`。
- 需要特定 applet 或新版本行为时，不要退回系统旧版 busybox（1.37 及更老）；直接走上面的默认路径。

## 使用工具与说明

重新打开 shell 或重新加载 shell 配置后，可直接按命令名调用：

```sh
rg --version
jaq --version
python3 --version
```

工具目录名就是命令名。参数、示例和平台注意事项以各目录的 `USAGE.md` 为准，例如 `tools/rg/USAGE.md`、`tools/python3/USAGE.md`。

## 卸载

`uninstall.sh` 默认仅移除此技能写入的 PATH 配置，保留技能文件和二进制。Teable 版如需删除所有由工具箱管理的版本化运行时目录，显式使用 `--purge-runtime`；非交互环境还需传 `--yes`：

```sh
sh /path/to/installed/tools/scripts/uninstall.sh
sh /path/to/installed/tools/scripts/uninstall.sh --yes --purge-runtime
```

清理运行时后，再由 Skills 管理器卸载本地技能：

```sh
npx skills remove --global tools
```

## 同步与维护

GitHub Actions 每 15 分钟检查 `otaku-say/ish-toolbox` 的 `tools/` Git tree。检测到变化时会校验哈希、文档、ELF 架构和静态链接，再更新本仓库的完整 `main` 工具目录并自动提交；也可在 Actions 页面手动运行。轻量兼容分支由 `main` 上的 profile 和构建器生成，不继承包含大型二进制的历史。

兼容性测试记录见 [references/compatibility-tests.md](references/compatibility-tests.md)。
