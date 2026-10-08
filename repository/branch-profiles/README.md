# Agent 分支策略

`main` 是完整发行分支，包含 `tools/` 技能和 amd64/arm64 二进制。平台分支由 main 构建，按各自 profile 的包大小、二进制打包策略、运行时来源、技能模板和历史策略生成。

GitHub Actions 在 main 的 push、定时或手动触发时运行校验与本地分支构建；默认不推送兼容分支。只有从 main 手动触发 workflow 并显式启用 `publish` 输入，才会调用发布器推送公开分支。命令行发布器也必须显式传入 `--push`。新增兼容平台时，添加 `<platform>.json` 与对应的 `SKILL.md.in`（模板不能直接命名为 `SKILL.md`），然后由分支构建工作流生成该平台分支。生成分支只保留目标技能树和构建元数据，不在主仓库技能目录中增加嵌套技能入口。


Teable profile 的技能包上限是 512000 字节，排除二进制，并将 main commit 写入 `RUNTIME_SOURCE_COMMIT`。构建输出使用独立 orphan 历史，避免安装端下载 main 的大文件历史。其他分支可声明自己的包大小和 payload 规则。

校验 profile 与生成包：

```sh
sh repository/scripts/validate-branch-profiles.sh
sh repository/scripts/build-agent-branch.sh teable "$PWD" /tmp/teable-package "$(git rev-parse HEAD)"
```
