---
name: tools
description: >-
  当用户需要在 Linux 沙箱中批量安装、更新、校验或卸载 ish-toolbox 工具集，或查找其中 rg、jaq、python3、ssh、curl 等命令的用法时，使用此工具箱技能。它是一个统一技能，不会把每个工具目录单独注册为 Agent 技能。
compatibility: >-
  目标发行版包括 Alpine、Debian、OpenCloudOS 和 OpenWrt，支持 Linux amd64/x86_64 与 arm64/aarch64；OpenWrt 仅限这两个架构。二进制为静态单文件。amd64 已完成安装、更新与运行测试；arm64 仅通过上游静态检查，未做运行时测试。PATH 配置目标为 POSIX shell、BusyBox ash、Bash 和 Zsh；本轮仅在本机 /bin/sh 测试，未运行 BusyBox ash。Teable 版运行时下载需要 curl、wget 或 uclient-fetch，并需要 sha256sum、BusyBox sha256sum 或 openssl 之一。
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

main 包含 46 个工具的 amd64 和 arm64 二进制。安装后只保留当前主机架构；Skills 管理器更新技能包时可能重新带入另一架构，因此更新后应运行 `scripts/install.sh`。若遗漏，已有 PATH 启动配置会在下一个 shell 启动时检测并裁剪，不会在每次命令调用时增加 wrapper 开销。

Teable 使用 `teable` 分支的轻量包。该包不含二进制；安装脚本从 `RUNTIME_SOURCE_COMMIT` 指定的 main commit 逐个下载当前架构文件，先校验 SHA256 再保存到 `${XDG_CACHE_HOME:-$HOME/.cache}/ish-toolbox-runtime/`，不写入只读的技能目录。不会下载或保留另一架构。分支构建及 512000 字节限制见仓库 `repository/branch-profiles/`。

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
