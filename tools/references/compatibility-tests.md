# 兼容性与测试范围

## 工具包

- 上游：`otaku-say/ish-toolbox` 的 `tools/` 目录，共 46 个工具；每个工具目录含 `USAGE.md`。
- `main` 包含 amd64/x86_64 与 arm64/aarch64 二进制及 `SHA256SUMS.amd64`、`SHA256SUMS.arm64`；安装验证当前架构后移除另一架构。
- Teable 包不含二进制，仅携带工具说明、生命周期脚本、两个架构的哈希清单和固定 `RUNTIME_SOURCE_COMMIT`。运行时按主机架构逐文件下载到技能目录之外的版本化运行时目录，并逐项校验 SHA256。
- 上游静态检查覆盖哈希、ELF 架构和静态链接；通过静态检查不代表已在该架构运行。

## 本轮验证

| 环境/架构 | 验证内容 | 结果 |
|---|---|---|
| amd64/x86_64 | main 包 install/verify/uninstall、46 个工具保留当前架构、PATH 配置幂等，以及新 shell 清理重新带入的 arm64 目录 | 临时目录测试通过 |
| arm64/aarch64 模拟 | mock `uname -m`；main 包保留 arm64、删除 amd64；新 shell 清理重新带入的 amd64 目录 | 临时目录测试通过；未执行 arm64 二进制 |
| Teable amd64 | 构建包、下载 46 个 amd64 文件、校验清单、重复安装无额外下载、损坏哈希失败后重试、删除所有有标记的版本化运行时 | mock 下载测试通过；未访问公开网络 |
| Teable 下载回退 | 屏蔽 curl/wget，使用 mock `uclient-fetch -O` 下载当前架构运行时 | 通过；未在 OpenWrt 设备实测 |
| 发行分支 | 构建包约 149 KB；临时 bare remote 首次发布为无父提交的 orphan 分支，内容仅含 `tools/`；无变化时重跑不产生更新 | 通过；验证使用本地临时 remote |
| Shell 语法 | 本机 `/bin/sh` 检查仓库 shell 脚本 | 通过；BusyBox 不可用，本轮未运行 ash |
| arm64 二进制 | 上游哈希、ELF 架构和静态链接检查 | 通过静态检查；未在 arm64 主机运行 |
| 各目标发行版 | Alpine、Debian、OpenCloudOS、OpenWrt 等 | 未逐发行版测试 |

amd64 测试在当前 Linux 主机执行。arm64 的架构选择用 mock `uname` 验证，但 arm64 程序未被执行。`uclient-fetch` 只以 mock 接口验证参数和传输流程，不能替代 OpenWrt 本机测试。BusyBox/ash 当前环境不可用，因此兼容性声明不包含本轮 ash 运行结果。

## 依赖与边界

main 包的安装和验证不需要下载器或 `tar`。Teable 首次安装/更新按优先级使用 PATH 中的 `curl`、`wget` 或 OpenWrt `uclient-fetch`；SHA256 校验使用 `sha256sum`、BusyBox `sha256sum` 或 `openssl`。临时目录通过基于进程 ID 的 `mkdir` 创建，不依赖 `mktemp`。直接将本工具箱加入 PATH，shell 启动配置会检查并清理另一架构，不会为每个命令增加 wrapper。

工具级兼容性、环境变量和系统服务要求以各自的 `USAGE.md` 为准。静态链接并不能保证每个工具在所有沙箱策略下都能访问网络、证书或系统服务。
