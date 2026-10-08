---
name: tools
description: >-
  在 Teable Agent 中使用 ish-toolbox 工具集，或查找 rg、jaq、python3、ssh、curl 等命令的用法。运行时二进制由安装脚本从受校验的 main 提交下载，不包含在技能安装包内。
compatibility: >-
  目标环境为 Alpine、Debian、OpenCloudOS 和 OpenWrt 上的 Linux amd64/x86_64、arm64/aarch64。安装需要访问 GitHub 下载运行时，使用 curl、wget 或 OpenWrt uclient-fetch，并使用 sha256sum、BusyBox sha256sum 或 openssl 校验。本轮仅在本机 POSIX /bin/sh 测试，未在 BusyBox ash 或 OpenWrt 设备验证。
---

# ish-toolbox Teable 版

这是供 Teable Agent 安装的轻量技能包。`tools/` 中只包含说明、清单和生命周期脚本；二进制在首次安装后下载到技能目录同级、按 main commit 隔离的运行时目录。安装脚本从自身位置动态推导路径，不搬移技能文件或已有二进制，只把当前架构的工具目录加入用户 PATH。

## 安装与更新

在 Teable 中安装 `teable` 分支的 `tools` 技能后运行：

```sh
sh /path/to/installed/tools/scripts/install.sh
sh /path/to/installed/tools/scripts/verify.sh
```

技能路径由安装环境决定，不要把示例路径写进脚本。更新技能说明后，先用 Teable 的技能管理方式更新技能，再运行：

```sh
sh /path/to/installed/tools/scripts/update.sh
```

运行时下载固定到此技能包声明的 main commit，只下载当前架构并按对应 SHA256 清单校验。下载失败或校验不通过时，不会把未校验文件加入 PATH。arm64 依据 amd64 实测和 arm64 静态检查默认兼容，但没有 arm64 运行时测试。

## 使用与卸载

重新打开 shell 或重新加载 shell 配置后，可直接按命令名调用，例如 `rg --version`、`jaq --version`、`python3 --version`。PATH 只加入当前主机架构对应的工具目录。

移除 PATH 配置：

```sh
sh /path/to/installed/tools/scripts/uninstall.sh
```

此操作保留技能文件和运行时二进制。明确要清理当前 Teable 版本下载的运行时目录时，使用 `--purge-runtime`；随后再通过 Teable 技能管理器卸载技能。

各工具参数见对应 `<tool>/USAGE.md`；兼容性和验证范围见 `references/compatibility-tests.md`。
