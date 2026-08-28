# GitHub Actions 发布控制面

GitHub Actions 是三个工程发布和版本回滚的唯一执行入口。本文件只记录控制面映射和无法从 workflow 单独推导的边界；当前目标 SHA 对应的 workflow、部署脚本、GitHub 配置和 run 才是执行事实源。

## 每次动态核验

发布或回滚前：

1. 核对仓库 origin、权威远端分支、准确 SHA 和 worktree。
2. 读取该 SHA 的 `.github/workflows/` 及其调用的部署脚本，确认 event、checkout、输入、GitHub Environment、目标服务、concurrency、测试/readiness 和失败恢复语义。
3. 只读查询启用的 workflow、Environment 保护规则、分支保护、未完成 run，以及候选目标的历史 run/attempt 和实际 checkout SHA。
4. 如果 Action 不能将操作绑定到准确 SHA、没有请求所需的入口，或当前配置与下述映射冲突，停止并报告；不得改用 SSH、手工制品复制、通过 SSH 直接重启服务或本机部署脚本补齐流程。

绿色 Action 只证明它实际执行的检查。代码版本恢复不能撤销已经 ACK 的消息、已提交的数据库/TOS 写入或其他外部副作用；这些属于独立的数据恢复任务。

## Crawler

- 仓库：`Lighthunter-PTE-ltd/loa-glabal-crawler`；控制面入口：`.github/workflows/deploy.yml`。
- 唯一可用环境是生产，权威部署分支是 `prod`。workflow 中的 `test`/`uat` 是历史目标，不得使用。
- 常规入口是合并到 `prod` 后触发 Action。手工 dispatch 时，目标环境输入与 workflow checkout ref 必须分别核验为预期的 `prod` 和准确 SHA；不能只看 `environment=prod`。
- 2026-08-25 快照中仓库没有 GitHub Environment。当前 workflow 会覆盖生产 JAR，未提供 previous-JAR 备份。
- 历史 run 的 rerun 只有在当前核验能证明新 attempt 仍 checkout 所需历史 SHA 时，才可作为版本回滚入口。

## Gateway

- 仓库：`Lighthunter-PTE-ltd/loa-data-gateway`；控制面入口：`.github/workflows/deploy.yml` 和 `.github/scripts/deploy-ecs.sh`。
- `test`、`main` push 会部署对应实例；`dev` 本身不部署。手工 dispatch 的目标由实际 workflow ref 决定。
- 2026-08-25 快照中仓库没有 GitHub Environment。
- `test` 与 `main` 共用服务器、生产依赖和 RabbitMQ queue；`test` 不是隔离验证环境。
- 当前脚本在 readiness 超时后尝试恢复 `.previous` binary 和 `.env.previous`，但必须等待 Action 终态并重新核验实际版本与健康状态。它不会撤销已处理消息或数据。
- 操作员版本回滚仍必须通过 Action 检出已核验的准确目标；如果当前入口不能做到这一点，应停止，而不是直接改服务器文件。

## Agent Lite

- 仓库：`Lighthunter-PTE-ltd/loa_agent_lite`；控制面入口：`.github/workflows/deploy-on-merge.yml`、`.github/workflows/release.yml` 和 `scripts/deploy-release-on-server.sh`。
- `dev` 是受保护的默认开发分支，不触发环境部署。`Deploy on merge` 只监听合并到 `test` 或 `main` 的 PR closed 事件，并要求 PR 实际已合并。
- `test` 对应 `lc-oc-test-lite`，`main` 对应 `lc-oc-prod`。Workflow 使用 PR 的 `merge_commit_sha` 作为 `TARGET_SHA`，checkout 后再次核对实际 HEAD，再执行 check、test、Leo runtime smoke、制品构建和部署。
- GitHub Environments 使用 custom branch policy：`lc-oc-test-lite` 只接受 `test`，`lc-oc-prod` 只接受 `main`。两者在 2026-08-28 核验时没有 required-reviewer 等 protection rules；分支限制不能替代 required reviewer。
- `test` 使用测试 API key、测试 SSH 目标和测试服务集合；`main` 使用生产 API key、bastion/生产 SSH 目标，并依次部署 `prod-a`、`prod-b`。环境选择、凭据选择、SSH 配置和部署目标都必须使用同一个 `TARGET_BRANCH` 判定，修改分支映射时要整体核对，不能只改 workflow trigger。
- 生产按 `prod-a` 后 `prod-b` 串行部署，不是跨主机事务。单机脚本的自动 rollback 只恢复该主机备份，且恢复后不重新验证 Gateway health 或 Worker；不得把它视为完整生产回滚。
- `.github/workflows/release.yml` 的手工 pre-release 只允许从 `test` 运行；stable release 仍由符合 `vX.Y.Z` 的 tag 触发。Release 与环境部署是不同控制面，绿色 Release 不证明测试或生产服务器已更新。
- 2026-08-28 分支迁移时先停用 `Deploy on merge`，再通过受保护分支 PR 依次同步 `dev -> test -> main`，最后恢复 workflow。迁移后的 `dev`、`test`、`main` tree 均为 `1c9b1bb1d05f089a40b6b40dfaa298f60f8f0d3a`，且迁移没有产生新的 Action run 或 Environment deployment；不得将此次控制面变更表述为一次应用部署。

## 快照与历史证据

上述日期信息用于发现配置漂移，不替代当前 GitHub 查询。具体历史 run ID、旧 SHA 和一次性发布观察应保留在带日期的验证记录或运行快照中，不应成为长期默认发布或回滚目标。
