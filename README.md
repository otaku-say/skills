# Agent 技能

本仓库存放可独立安装的 Agent 技能。所有技能正文、参考说明、仓库文档和脚本注释均以简体中文为主语言；命令名、代码标识、协议字段、专有名称和 CLI 原始帮助输出保留原文。

## 技能索引

| 技能 | 用途 | 范围边界 |
|---|---|---|
| [`aiod-cli/`](aiod-cli/SKILL.md) | 在已有 CubeSandbox 中执行命令、操作文件、会话、PTY、代码、浏览器、桌面和 MCP Hub | 仅负责数据面，不负责创建或销毁沙箱 |
| [`cube-cli/`](cube-cli/SKILL.md) | 管理 CubeSandbox 生命周期、模板、快照、持久卷和端口 | 负责控制面；沙箱内部操作使用 aiod-cli |

使用 Skills CLI 安装单个或两个技能：

```sh
npx skills add otaku-say/skills --skill aiod-cli -g
npx skills add otaku-say/skills --skill cube-cli -g
```

更新已安装技能：`npx skills update <skill-name> -g`。卸载技能：`npx skills remove --global <skill-name>`。每个 CLI 技能均在自己的目录中保留 wrapper、两个架构的二进制、更新脚本和校验值。

## 目录结构

每个技能必须有 `<技能名>/SKILL.md`，且 frontmatter 的 `name` 必须与目录名一致。按需添加 `references/`、`scripts/`、`assets/` 和 `bin/` 等目录。CLI 技能结构如下：

```text
<cli-技能>/
├── SKILL.md
├── bin/
│   ├── <cli>             # 架构选择 wrapper
│   ├── amd64/<cli>       # x86_64 Linux 二进制
│   ├── arm64/<cli>       # aarch64 Linux 二进制
│   ├── update.sh
│   ├── verify.sh
│   └── SHA256SUMS
└── references/
    ├── cli-reference.txt
    └── compatibility-tests.md
```

维护新技能或修改仓库规则时，先阅读根目录 [`AGENTS.md`](AGENTS.md) 和 [`CONTRIBUTING.md`](CONTRIBUTING.md)。提交前运行：

```sh
sh scripts/validate-skills.sh
```

测试范围及未覆盖平台见各技能目录下的 `references/compatibility-tests.md`。
