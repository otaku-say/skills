---
name: cube-cli
description: >-
  当用户请求创建、列出、检查、选择模板、续期、暂停、恢复、快照、克隆、回滚或删除 CubeSandbox，管理持久卷，检查沙箱端口或排查控制面连接时，使用本技能目录中的 cube-cli。本技能负责沙箱控制面和生命周期；沙箱内的命令、文件、PTY、代码、浏览器和桌面操作使用 aiod-cli。触发词包括 cube-cli、CubeSandbox、沙箱生命周期、模板、快照、持久卷和 CUBESANDBOX_API_URL。
compatibility: 适用于带静态 musl 构建的 Linux amd64/x86_64 与 arm64/aarch64。维护脚本优先使用 curl、gawk、openssl，或回退到系统 awk、sha256sum。需配置 CubeSandbox 控制面 URL，以及部署要求的凭据。测试范围见 references/compatibility-tests.md。
---

# cube-cli

使用 `cube-cli` 管理 **CubeSandbox 控制面**：选择镜像、创建和检查沙箱、管理生命周期与持久化资源、查看可访问端口。沙箱创建后，使用独立的 `aiod-cli` 技能执行内部操作。

## 安装和配置

wrapper 会按主机架构选择 Linux amd64/x86_64 或 arm64/aarch64 二进制。静态 musl 构建面向 Debian/Ubuntu、Fedora/RHEL、Arch、Alpine 等主流 Linux 发行版；本轮仅在 x86_64 环境运行。将未实测的发行版或 arm64 运行时视为未验证，详情见[兼容性与测试结果](references/compatibility-tests.md)。

```sh
npx skills add otaku-say/skills --skill cube-cli -g
CUBE_SKILL_DIR="/path/to/installed/cube-cli"
sh "$CUBE_SKILL_DIR/scripts/install.sh"
sh "$CUBE_SKILL_DIR/bin/cube-cli" version
```

`install.sh` 从脚本自身路径推导技能目录并配置 PATH。main 完整包会验证本地当前架构二进制并裁剪另一架构；Teable 镜像不带二进制，会从该技能的 `RUNTIME_SOURCE_COMMIT` 指定的 main commit 下载并校验当前架构文件，放入 `${TEABLE_SKILLS_RUNTIME_HOME:-$HOME/workspace/.cache/otaku-skills-runtime}/cube-cli/`，并将缓存中的当前架构目录加入 PATH，不写只读技能目录。默认运行时位于 Teable 持久 workspace 下，跨 sandbox 重建保留；显式设置 `TEABLE_SKILLS_RUNTIME_HOME` 时必须指向持久目录。即使导入器去掉了技能 wrapper 的执行位，PATH 中的原生 CLI 仍可直接调用；脚本示例通过 `sh` 调用 wrapper。main 包 wrapper 在下一次调用时继续清理另一架构文件。

在运行环境的受保护配置中设置部署变量，不要将它们写入仓库或命令记录：

| 变量 | 用途 | 说明 |
|---|---|---|
| `CUBESANDBOX_API_URL` | 控制面操作 | CubeSandbox 控制面基础 URL |
| `CUBESANDBOX_API_KEY` | 需要 API-key 认证的部署 | 控制面 API key；当前 CLI 部署可能允许省略 |
| `CUBESANDBOX_PROXY_URL` | 数据面操作，如 `exec`、文件访问和端口 URL | 数据面网关基础 URL |
| `CUBESANDBOX_AGENT_NAME` | 可选 | 新建沙箱时默认使用的 Agent 标签 |

示例中只能使用占位符，禁止提交真实域名、令牌、沙箱 ID 或部署专属信息。检查配置时不得输出秘密值。

维护脚本通过当前 PATH 调用 `curl`、`awk` 及 `sha256sum`、BusyBox `sha256sum` 或 `openssl`。如果使用 ish-toolbox 提供这些辅助工具，先按其说明运行安装脚本；无需设置静态安装目录变量。具体测试结果见兼容性说明。

```sh
CUBE_SKILL_DIR="/path/to/cube-cli"
sh "$CUBE_SKILL_DIR/bin/cube-cli" version
sh "$CUBE_SKILL_DIR/bin/cube-cli" help
```

远程数据面路径的形式如下：

```text
$CUBESANDBOX_PROXY_URL/sandbox/<sandbox-id>/<port>/<path>
```

沙箱 ID 属于能力凭据：持有有效 URL 的人可能获得访问权限，不得公开。数据面路由取决于部署配置，不得猜测主机名或直接连接沙箱 IP。

## 按能力选择模板

模板 ID 可能随重建变化，不要硬编码。使用能力选择器并检查实时结果：

```sh
sh "$CUBE_SKILL_DIR/bin/cube-cli" tpl-caps
sh "$CUBE_SKILL_DIR/bin/cube-cli" tpl-pick --need=browser
```

- `code` 足以执行 Shell、文件、Python、Node 和编译任务。
- `browser` 包含 `code` 能力，并增加浏览器服务。
- `desktop` 包含浏览器能力，并增加桌面/计算机操作服务。

`--need` 是包含关系：`desktop` 满足 `browser` 和 `code`，`browser` 满足 `code`。选择能够完成任务的最低能力镜像。`tpl-caps --probe` 会创建临时资源；未经用户授权且没有明确清理方案时不要运行。

## 创建并检查沙箱

创建前确认任务，选择最低必要能力，并设置明确的空闲超时。创建沙箱可能产生费用。使用不含秘密的元数据区分并发任务，不要将凭据放入元数据。

```sh
sh "$CUBE_SKILL_DIR/bin/cube-cli" new \
  --need=code \
  --timeout=3600 \
  --agent="<agent-name>" \
  --task="<short task description>"
```

捕获命令返回的沙箱 ID 并赋给变量，再检查状态：

```sh
SID="<sandbox-id>"
sh "$CUBE_SKILL_DIR/bin/cube-cli" ls --json
sh "$CUBE_SKILL_DIR/bin/cube-cli" info "$SID" --json
sh "$CUBE_SKILL_DIR/bin/cube-cli" logs "$SID" --tail=50
```

创建成功不代表所有服务均已就绪。对于 AIO 镜像，使用实际配置的代理域名和沙箱 ID 设置 `SANDBOX_BASE`，并在派发工作前确认 `aiod-cli health` 正常。

## 生命周期操作

```sh
SID="<sandbox-id>"
sh "$CUBE_SKILL_DIR/bin/cube-cli" refresh "$SID" --duration=300
sh "$CUBE_SKILL_DIR/bin/cube-cli" timeout "$SID" --timeout=7200
sh "$CUBE_SKILL_DIR/bin/cube-cli" pause "$SID"
sh "$CUBE_SKILL_DIR/bin/cube-cli" resume "$SID"
sh "$CUBE_SKILL_DIR/bin/cube-cli" net "$SID" --no-internet
```

`timeout` 设置空闲回收窗口，不保证沙箱的总存活时间。参数以部署中 CLI 的帮助为准：

```sh
sh "$CUBE_SKILL_DIR/bin/cube-cli" help all
sh "$CUBE_SKILL_DIR/bin/cube-cli" help new
```

`rm`、删除卷或快照以及破坏性回滚/覆盖都可能造成不可恢复的数据丢失，执行前必须确认。说明具体受影响的沙箱、卷或快照及数据影响范围。已有明确 ID 时不要根据名称猜测目标。

## 快照、克隆和持久化

```sh
SID="<sandbox-id>"
LABEL="<label>"
SNAPSHOT_ID=$(sh "$CUBE_SKILL_DIR/bin/cube-cli" snap "$SID" --name="$LABEL")
sh "$CUBE_SKILL_DIR/bin/cube-cli" snap-ls --sandbox="$SID"
sh "$CUBE_SKILL_DIR/bin/cube-cli" clone "$SID" --n=1
sh "$CUBE_SKILL_DIR/bin/cube-cli" vol-ls
```

回滚会改变目标沙箱的文件系统和内存状态。先确认目标快照并说明影响，再取得用户明确批准。克隆会创建新沙箱，需记录命令返回的新 ID。

快照、回滚和克隆不会复制或恢复已挂载卷或主机挂载中的数据，应将这些存储视为独立持久化系统。卷可能被多个沙箱共享；删除前检查引用并分离所有沙箱。主机挂载因部署而异，可能直接写入宿主机数据；只有用户明确指定路径和访问模式后才可配置。

## 端口和数据面访问

```sh
SID="<sandbox-id>"
sh "$CUBE_SKILL_DIR/bin/cube-cli" ports "$SID"
```

依据实际监听端口和返回的网关 URL 操作，不要只依据模板声明。服务通常需要绑定 `0.0.0.0` 才能通过代理访问；绑定到回环地址的服务只能在沙箱内部使用。不要暴露含有私密或敏感数据的服务。能力 URL 应按凭据保护。

## 故障处理

- `401`：确认控制面 key 已配置且有效；不得打印其值。
- 找不到模板或没有符合条件的 READY 模板：重新列出模板并按当前能力选择，不要复用过期 ID。
- 数据面 `502`：使用 `ports` 和沙箱内 CLI 检查服务是否监听及绑定到可访问地址。
- 生命周期操作遇到 `503`：遵循 `Retry-After`，等待指定时间后再重试同一操作。
- 新沙箱暂时未就绪：等待相关健康检查通过，不要重复创建请求。
- 请求大小或时长受限：在沙箱内执行工作，或使用 `aiod-cli` 异步任务及分块传输。

不要盲目重试非幂等生命周期操作。先检查沙箱状态，确认原请求是否已经完成。

## 更新和卸载

更新技能说明或配套文件后，先更新技能包，再运行安装脚本，以重新校验并清除包管理器重新带入的另一架构二进制：

```sh
npx skills update cube-cli -g
CUBE_SKILL_DIR="/path/to/installed/cube-cli"
sh "$CUBE_SKILL_DIR/scripts/install.sh"
```

CLI 二进制独立发布。`scripts/update.sh` 在 main 完整包中只下载并校验当前架构的 Release asset；Teable 镜像则从固定 main commit 下载清单对应的当前架构二进制到 `${TEABLE_SKILLS_RUNTIME_HOME:-$HOME/workspace/.cache/otaku-skills-runtime}/cube-cli/`。两种模式都会重新运行安装流程：

```sh
sh "$CUBE_SKILL_DIR/scripts/update.sh"
sh "$CUBE_SKILL_DIR/scripts/verify.sh"
```

`verify.sh` 离线校验当前架构二进制、wrapper 和 SHA256 清单；它不联网检查上游版本。main 包需要强制重新下载时传 `--force`；Teable 缓存由固定 commit 管理。上游 Release 地址可通过 `CUBE_CLI_RELEASE_BASE` 覆盖。

卸载先清除本技能写入的 PATH 配置，再由 Skills CLI 移除本地技能文件：

```sh
sh "$CUBE_SKILL_DIR/scripts/uninstall.sh"
# 需要同时清除该技能的受管理缓存时显式执行：
sh "$CUBE_SKILL_DIR/scripts/uninstall.sh" --yes --purge-runtime
npx skills remove --global cube-cli
```

这不会删除任何远端沙箱、卷、快照或用户数据；远端清理需另行处理并先取得明确批准。

## 技能目录内文件

- `bin/cube-cli` 根据主机架构选择 main 包本地二进制或 Teable 用户缓存中的运行时。
- main 源包包含 `bin/amd64/cube-cli` 与 `bin/arm64/cube-cli`；安装后仅保留当前架构。
- `bin/SHA256SUMS` 保存 Release 清单中的当前架构哈希；main 源包初始包含两个架构条目。
- `scripts/install.sh` 验证、裁剪非当前架构并幂等配置 PATH。
- `scripts/update.sh` 按安装模式更新当前架构二进制并重新执行安装后处理；`scripts/update-runtime.sh` 用于 Teable 的固定 commit 缓存运行时。
- `scripts/verify.sh` 离线校验当前架构及 SHA256 清单；`scripts/uninstall.sh` 清理 PATH，可通过显式 `--purge-runtime` 清理受管理缓存。
- [兼容性与测试结果](references/compatibility-tests.md)区分已测试行为与尚未执行的架构/发行版。
- `references/cli-reference.txt` 保存 CLI 0.2.0 的完整 `help all` 输出；若版本不同，以已安装二进制的帮助为准。
