# Agent 分支策略

`main` 是完整发行分支，包含仓库文档、规则文件、所有技能和 amd64/arm64 二进制。`teable` 分支镜像 main 的完整文件树，包括 `README.md`、`AGENTS.md`、`CONTRIBUTING.md`、未来新增的技能，以及构建和校验资料；唯一有意省略的是技能目录中的架构二进制目录。分支使用独立 orphan 历史，避免 Teable 获取 main 的二进制历史。

main 的每次 push 都会校验并重新生成 Teable 镜像，随后同步公开 `teable` 分支。定时任务如果同步了上游工具并产生 main 内容更新，也会在同一次运行中更新镜像。手动触发仍可通过 `publish` 输入选择是否发布。命令行发布器默认 dry-run，只有显式传入 `--push` 才会推送。

构建器自动发现仓库根目录下含 `SKILL.md` 的技能目录，并递归删除名为 `amd64` 或 `arm64` 的架构目录。含二进制的技能会获得固定 `RUNTIME_SOURCE_COMMIT`；其生命周期脚本必须支持从该 main commit 只下载当前架构、校验 SHA256，将运行时放入 `${TEABLE_SKILLS_RUNTIME_HOME:-$HOME/workspace/.cache/otaku-skills-runtime}/<skill>`。Teable 默认将运行时放在持久 workspace 下；显式设置 `TEABLE_SKILLS_RUNTIME_HOME` 时必须指向持久目录，且不能写入只读技能目录。新增技能时遵守该规则即可随 main 自动进入 Teable 镜像，无需维护技能列表；无二进制的技能不需要运行时标记。

Teable 完整镜像总大小上限为 512000 字节。构建会检查所有技能具备 install/update/uninstall/verify 脚本，确认架构目录已移除，并扫描是否残留 ELF、Mach-O 或 PE 二进制。

校验 profile 与构建包：

```sh
sh repository/scripts/validate-skills.sh
sh repository/scripts/validate-branch-profiles.sh
sh repository/scripts/build-agent-branch.sh teable "$PWD" /tmp/teable-package "$(git rev-parse HEAD)"
```
