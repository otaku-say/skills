---
name: tools
description: >-
  当用户需要在 Linux 沙箱中批量安装、更新、校验或卸载 ish-toolbox 工具集，或查找其中 rg、jaq、python3、ssh、curl 等命令的用法时，使用此工具箱技能。它是一个统一技能，不会把每个工具目录单独注册为 Agent 技能。
compatibility: >-
  适用于 Linux amd64/x86_64 和 arm64/aarch64。工具是静态单文件二进制；安装脚本需要 git，或 curl/wget、tar，以及 sha256sum/BusyBox sha256sum/openssl 之一。PATH 配置面向 POSIX shell、Bash 和 Zsh。
---

# ish-toolbox 工具箱

从仓库同步的一组静态 Linux 命令行工具。一个 `tools` 目录对应一个 Agent 技能；`tools/<工具名>/USAGE.md` 是该工具自己的说明，不需要也不应把每个工具注册成独立技能。

## 安装

先按目标 Agent 的 Skills CLI 安装本技能，再在 Linux 沙箱中运行安装脚本：

```sh
npx skills add otaku-say/skills --skill tools -g
sh /path/to/installed/tools/scripts/install.sh
```

安装脚本从本仓库稀疏下载 `tools/`，校验两个架构的文件和说明，放到固定目录 `~/.local/share/ish-toolbox/`，并为每个命令生成架构选择入口。它会在 `~/.profile`、`~/.bashrc`、`~/.bash_profile` 和 `~/.zshrc` 中幂等添加 `PATH` 配置，不需要 root。当前 shell 不会被父进程脚本直接修改；重新打开 shell，或执行：

```sh
export PATH="$HOME/.local/share/ish-toolbox/bin:$PATH"
```

首次安装和升级都可运行 `install.sh`；需要再次从仓库取回上游工具、二进制和说明时运行 `update.sh`：

```sh
sh /path/to/installed/tools/scripts/update.sh
sh /path/to/installed/tools/scripts/verify.sh
```

更新 Agent 技能说明和维护脚本时使用 `npx skills update tools -g`；它与下载工具二进制是两个独立步骤。

## 使用工具与说明

安装后直接按命令名调用，例如：

```sh
rg --version
jaq --version
python3 --version
```

工具入口会按当前 `uname -m` 选择 amd64 或 arm64 二进制。工具目录名就是命令名；具体参数、示例和平台注意事项以各目录的 `USAGE.md` 为准，例如 `tools/rg/USAGE.md`、`tools/python3/USAGE.md`。这些逐工具文档与二进制从上游同一版本同步。

## 卸载

卸载会删除此工具箱管理的 `~/.local/share/ish-toolbox/`，并移除此技能写入的 PATH 配置；不会删除技能安装目录、系统包、其他用户文件或远端沙箱数据。脚本要求交互确认；自动化环境可显式传 `--yes`：

```sh
sh /path/to/installed/tools/scripts/uninstall.sh
# 非交互环境
sh /path/to/installed/tools/scripts/uninstall.sh --yes
```

若还要移除此 Agent 技能，再单独运行 `npx skills remove --global tools`。

## 同步与维护

GitHub Actions 每 15 分钟检查 `otaku-say/ish-toolbox` 的 `tools/` Git tree。检测到变化时会校验哈希、文档、ELF 架构和静态链接，再更新本仓库的工具目录并自动提交到 `main`；也可在 Actions 页面手动运行。技能入口、维护脚本和兼容性说明由本仓库维护，不会被上游目录覆盖。

兼容性测试记录见 [references/compatibility-tests.md](references/compatibility-tests.md)。
