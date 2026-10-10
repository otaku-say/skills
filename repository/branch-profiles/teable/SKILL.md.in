---
name: tools
description: >-
  在 Teable Agent 的 Linux 沙箱中安装、更新、校验和使用 ish-toolbox 命令行工具，或查询 rg、jaq、python3、ssh、curl 等命令的参数与用法。
compatibility: >-
  支持 Linux amd64/x86_64 与 arm64/aarch64 的 Alpine、Debian、OpenCloudOS；OpenWrt 仅限这两个架构。安装需 curl、wget 或 uclient-fetch 之一下载运行时，并需 sha256sum 或 openssl 校验。
---

# ish-toolbox

该技能将工具箱中的命令作为一个整体管理。各工具的参数和平台注意事项见对应的 `tools/<tool>/USAGE.md`，逐工具说明不是独立技能。

## 安装与更新

从 Teable `teable` 分支安装技能后，运行：

```sh
sh /path/to/installed/tools/scripts/install.sh
sh /path/to/installed/tools/scripts/verify.sh
```

安装只下载当前架构工具到 `${TEABLE_SKILLS_RUNTIME_HOME:-$HOME/workspace/.cache/otaku-skills-runtime}` 并配置用户 shell PATH；默认缓存位于持久 workspace，不写只读技能目录，也不更改系统配置。

更新技能说明或脚本后，先通过 Teable 技能管理器更新技能，再运行 `install.sh`。单独更新工具运行时则运行：

```sh
sh /path/to/installed/tools/scripts/update.sh
sh /path/to/installed/tools/scripts/verify.sh
```

重复安装和更新不会添加重复的 PATH 配置。重新打开 shell 或重新加载 shell 配置后，可直接调用工具，例如 `rg --version`、`jaq --version`、`python3 --version`。

## 卸载

默认仅移除此技能管理的 PATH 配置，保留技能文件和运行时；运行卸载脚本清理 PATH：

```sh
sh /path/to/installed/tools/scripts/uninstall.sh
```

如需删除工具箱管理的全部版本化运行时目录，运行：

```sh
sh /path/to/installed/tools/scripts/uninstall.sh --yes --purge-runtime
```

之后再通过 Teable 技能管理器卸载本地技能。各工具用法见对应 `tools/<tool>/USAGE.md`；兼容性与验证范围见 `references/compatibility-tests.md`。
