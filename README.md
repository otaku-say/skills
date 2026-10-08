# Agent 技能

本仓库存放可独立安装的 Agent 技能。所有技能正文、参考说明、仓库文档和脚本提示均以简体中文为主；命令名、代码标识、协议字段、专有名称和 CLI 原始帮助输出保留原文。

## 技能索引

| 技能 | 用途 | 范围边界 |
|---|---|---|
| [`aiod-cli/`](aiod-cli/SKILL.md) | 在已有 CubeSandbox 中执行命令、操作文件、会话、PTY、代码、浏览器、桌面和 MCP Hub | 仅负责数据面，不负责创建或销毁沙箱 |
| [`cube-cli/`](cube-cli/SKILL.md) | 管理 CubeSandbox 生命周期、模板、快照、持久卷和端口 | 负责控制面；沙箱内部操作使用 aiod-cli |
| [`tools/`](tools/SKILL.md) | 在 Linux 沙箱中维护 46 个静态命令行工具 | 一个工具箱技能；逐工具 `USAGE.md` 不单独注册 |

## 安装与生命周期

从 main 安装技能：

```sh
npx skills add otaku-say/skills --skill aiod-cli -g
npx skills add otaku-say/skills --skill cube-cli -g
npx skills add otaku-say/skills --skill tools -g
```

每个技能目录必须提供 `scripts/install.sh`、`scripts/update.sh`、`scripts/uninstall.sh` 和 `scripts/verify.sh`。安装后运行 `install.sh`；更新技能包后也应立即运行 `install.sh`，以重新校验、配置 PATH 并裁掉非当前架构二进制。CLI wrapper 会在下一次命令调用时自清理，工具箱的 PATH 启动配置会在下一次 shell 启动时自清理，因此不依赖 Skills 管理器提供 post-update hook，也不为工具箱每次命令增加 wrapper 开销。

更新与验证示例：

```sh
npx skills update <skill-name> -g
sh /path/to/installed/<skill-name>/scripts/install.sh
sh /path/to/installed/<skill-name>/scripts/update.sh
sh /path/to/installed/<skill-name>/scripts/verify.sh
```

卸载时先运行该技能的 `scripts/uninstall.sh` 清理其 PATH/运行时配置，再由 Skills CLI 删除本地技能文件：

```sh
sh /path/to/installed/<skill-name>/scripts/uninstall.sh
npx skills remove --global <skill-name>
```

脚本从自身位置推导安装路径，不把 `/home/...`、`~/.local/share/...` 或某个 Agent 的技能目录写死。卸载只删除技能自身管理的配置或用户明确指定清理的运行时，不影响远端沙箱或用户数据。

## 工具箱发行分支

`main` 保留完整 `tools/` 技能及 amd64/arm64 二进制。首次运行 `tools/scripts/install.sh` 时识别主机架构、校验并删除另一架构的本地二进制目录，然后通过 PATH 暴露当前架构命令。

Teable 使用由 main 构建器生成的 `teable` 兼容分支。GitHub Actions 默认只校验和本地构建；仅 main 上手动触发并显式启用 `publish` 时推送公开分支。Teable 分支采用独立 orphan 历史，技能包剔除二进制并限制在 512000 字节以内；安装时只从固定 main commit 下载当前架构的二进制并按 SHA256 校验。未来兼容分支由 main 的 branch profile 声明包大小、payload 和历史规则，再由同一构建器生成。策略见 [`repository/branch-profiles/README.md`](repository/branch-profiles/README.md)。

## 目录与维护

每个技能入口是 `<skill-name>/SKILL.md`，frontmatter 的 `name` 必须与目录名一致。技能专属脚本、参考和资源放在自身目录；仓库维护脚本、生命周期脚本模板和分支模板位于 `repository/`。根目录不直接放置 `scripts/` 或 `templates/`。

维护前阅读根目录 [`AGENTS.md`](AGENTS.md) 与 [`CONTRIBUTING.md`](CONTRIBUTING.md)。提交前运行：

```sh
sh repository/scripts/validate-skills.sh
sh repository/scripts/validate-branch-profiles.sh
```

各技能的兼容性文档记录真实测试结果和未覆盖平台。仅完成静态检查的架构不得描述为已通过运行时测试。
