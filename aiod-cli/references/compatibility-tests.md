# 兼容性与测试结果

CLI 版本：`0.2.0`。二进制来源与兼容性声明以该版本的 Release 为准。

| 测试项 | 结果 |
|---|---|
| Linux `amd64`/`x86_64` 二进制 | 通过：musl ELF；在 x86_64 Linux 上执行过 CLI 与 aiod API 流程 |
| Linux `arm64`/`aarch64` 二进制 | 通过：Release SHA256、ELF 架构和静态链接检查；未在 arm64 主机执行 |
| 当前架构更新 | 在隔离临时副本中以本地 Release mock 测试；amd64 仅请求 amd64 资产，没有请求 arm64 资产 |
| 更新失败保护 | mock 资产 SHA256 错误时更新失败，现有二进制校验值保持不变；更正资产后重试通过 |
| 技能包更新后的架构裁剪 | 模拟重新带入 arm64 目录；amd64 wrapper 首次调用时清除该目录并执行本机 CLI |
| arm64 安装选择 | mock `uname -m` 为 `aarch64`；install 和 verify 选择 arm64 并删除 amd64 目录，未执行 arm64 二进制 |
| 安装、PATH 与卸载幂等性 | 临时 HOME 中重复 install/uninstall；PATH 区块不重复，卸载只清理本技能区块 |
| Shell 语法 | 本机 `/bin/sh` 下的仓库 `.sh` 文件通过 `sh -n`；BusyBox 不可用，本轮未运行 ash |
| 版本与帮助 | 通过：版本、`help all` 和 81 个命令帮助入口（含别名） |
| aiod 数据面流程 | 通过：健康检查、沙箱信息、同步命令、Python、文件读写与 put/get、异步任务/日志、命令会话和 PTY 操作 |
| 浏览器和桌面 API | 未测试：所用 CubeSandbox 镜像不具备浏览器或桌面能力 |
| Teable amd64 缓存运行时 | 完整镜像只含脚本和清单；在只读技能包和临时 XDG 缓存中安装、重复校验、执行版本命令并卸载 | 本地 file:// 主分支二进制夹具通过；未访问公开网络或 Teable Skills 服务 |
| Teable 下载失败保护 | aiod-cli 源文件 SHA256 错误时不得留下运行时；更正来源后重新安装 | 通过；仅下载主机架构 |
| Skills CLI 实际安装/更新/卸载 | 未执行；生命周期验证使用只读包模拟，没有声称 Skills CLI 本身已实测 |

静态 musl 构建面向使用 glibc 或 musl 的 Linux 发行版。除已执行的 x86_64 Linux 测试外，Debian/Ubuntu、Fedora/RHEL、Arch、Alpine 等发行版的独立验证及原生 arm64 运行验证仍未完成。

维护脚本优先使用 PATH 中的 `curl`、`awk` 和 SHA256 工具；可将 `ish-toolbox` 的工具目录通过 `ISH_TOOLBOX_BIN` 加入更新脚本的 PATH。toolbox 提供 `curl`、`gawk`、`openssl`，不提供独立 `sha256sum` 或 `mktemp`；脚本可回退到系统 `awk`/`sha256sum`，并用基于进程 ID 的 `mkdir` 创建临时目录。
