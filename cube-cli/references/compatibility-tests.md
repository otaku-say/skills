# 兼容性与测试结果

本次测试的 CLI 版本：`0.2.0`。

| 测试项 | 结果 |
|---|---|
| Linux `amd64`/`x86_64` 二进制 | 通过：静态链接的 musl ELF；已在 x86_64 Linux 上执行 |
| Linux `arm64`/`aarch64` 二进制 | 通过：已检查 ELF 架构、静态链接和 Release SHA256；未在本机执行 |
| `update.sh --force` | 通过：下载两个架构的 Release 文件并校验 SHA256 |
| `verify.sh` | 通过：两个架构文件均与上游 Release 清单一致 |
| POSIX Shell 语法 | 通过：使用本机 `/bin/sh` 检查 |
| 版本与 `help all` | 通过 |
| 单命令帮助 | 通过：61 个入口，含别名 |
| `ish-toolbox` 辅助工具 | 通过：使用其 x86_64 静态 `curl`、`gawk`、`openssl` |
| toolbox 架构与完整性 doctor | amd64、arm64 均通过哈希、ELF 架构和静态链接检查；未实际执行 arm64 程序 |
| 控制面操作 | 通过：健康检查、模板选择、沙箱列表/详情/日志/端口 |
| 沙箱生命周期 | 通过：创建、设置空闲超时、暂停、恢复，并在确认后删除临时测试沙箱 |
| 快照 | 暂停/恢复后运行 `snap-ls`，结果为空；未测试独立快照、克隆、回滚或持久卷操作 |
| Skills CLI 安装/更新/卸载 | 未执行；这里只记录命令用法，不声称这些生命周期命令已经实测 |

当前 `ish-toolbox` 不含独立的 `sha256sum` 或 `mktemp`。维护脚本优先使用其中的 `curl`、`gawk`、`openssl`，并回退到系统 `awk`/`sha256sum`；临时目录使用基于进程 ID 的 `mkdir` 创建，不依赖 `mktemp`。

静态 musl 构建的目标是兼容使用 glibc 或 musl 的主流 Linux 发行版。本次只在可用的 x86_64 Linux 主机执行 CLI；控制面生命周期测试使用 Ubuntu 22.04 x86_64 模板。Debian/Ubuntu、Fedora/RHEL、Arch、Alpine 等发行版的独立运行验证，以及原生 arm64 运行验证，仍未完成；不得将这些平台描述为本次已实测。
