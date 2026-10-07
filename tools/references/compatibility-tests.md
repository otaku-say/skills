# 兼容性与测试范围

## 工具包来源

- 上游：`otaku-say/ish-toolbox` 的 `tools/` 目录。
- 工具数量：46；每个工具目录均带 `USAGE.md`。
- 架构：amd64/x86_64 与 arm64/aarch64，各 46 个静态单文件二进制。
- 上游提供 `SHA256SUMS.amd64`、`SHA256SUMS.arm64` 和 `DOCS.sha256`。同步和安装前逐项校验所有列出的文件。
- 静态链接和 ELF 架构由上游 `scripts/doctor.sh` 检查；仅通过静态检查的架构不代表已在该架构运行。

## 运行环境与范围

安装入口使用 POSIX `/bin/sh`，调用 git 稀疏检出；没有可用 git 时回退到 curl 或 wget 加 tar。校验使用 sha256sum、BusyBox sha256sum 或 openssl。PATH 配置针对常见 POSIX shell、Bash 和 Zsh 启动文件。

| 环境/架构 | 验证范围 | 状态 |
|---|---|---|
| 当前 Linux 沙箱 amd64/x86_64 | 安装、哈希校验、PATH 配置、命令执行、卸载 | 由维护者逐次记录 |
| CubeSandbox amd64/x86_64 | 安装、哈希校验、PATH 配置、命令执行、卸载 | 由维护者逐次记录 |
| arm64/aarch64 | 上游哈希、ELF 架构和静态链接检查 | 未在本机运行时验证 |
| Debian/Ubuntu、Fedora/RHEL、Arch、Alpine | 静态 musl 二进制可减少发行版 libc 差异；具体系统仍需按目标环境测试 | 未逐一验证 |

安装依赖：git，或 curl/wget 与 tar；SHA256 校验需要 sha256sum、BusyBox 或 openssl。执行二进制不需要安装系统包，但个别工具连接网络、证书或调用系统服务时仍可能受沙箱策略影响，详见对应 `USAGE.md`。

## 维护者记录

每次发布前，在下表记录真实测试结果；不要将静态检查写成运行测试。尚未执行时保留“未验证”。

| 日期 | OS/镜像 | 架构 | 测试内容 | 结果 |
|---|---|---|---|---|
| 2026-10-07 | Debian GNU/Linux 13 (trixie) | amd64/x86_64 | 连续两次安装、更新、校验、PATH 加载和卸载；运行 rg、jaq、python3；无效源目录更新失败后确认原二进制不变 | 通过 |
| 2026-10-07 | CubeSandbox Linux | amd64/x86_64 | 连续安装、校验、运行 rg/jaq/python3、两次更新、失败源保护、登录 shell PATH 加载和两次卸载 | 通过；测试后已回收沙箱 |
| 2026-10-07 | 上游静态检查 | amd64 与 arm64 | `scripts/doctor.sh` 哈希、ELF 架构和无 PT_INTERP/NEEDED 检查 | 两架构通过；arm64 未运行 |
