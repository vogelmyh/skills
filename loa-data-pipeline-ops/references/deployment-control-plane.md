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

- 仓库：`Lighthunter-PTE-ltd/loa_agent_lite`；控制面入口：`.github/workflows/release.yml`、`deploy-prerelease.yml`、`deploy-production.yml` 和 `scripts/deploy-release-on-server.sh`。
- `main` 的成功 Release 会自动部署 prerelease 到测试环境。生产部署为手工 Action；当前 workflow 要求 `ref=prod`，并从 `prod` 分支构建。
- GitHub Environments 为 `lc-oc-test-lite` 和 `lc-oc-prod`。2026-08-25 快照中二者没有 required-reviewer 等 protection rules。
- 生产按 `prod-a` 后 `prod-b` 串行部署，不是跨主机事务。单机脚本的自动 rollback 只恢复该主机备份，且恢复后不重新验证 Gateway health 或 Worker；不得把它视为完整生产回滚。
- 当前生产 workflow 不接受不可变历史 commit 作为部署输入。除非更新后的 workflow 已提供并核验准确 SHA 入口，否则不得声称 rerun 历史生产 run 会重新部署其原始代码，也不得执行操作员版本回滚。

## 快照与历史证据

上述日期信息用于发现配置漂移，不替代当前 GitHub 查询。具体历史 run ID、旧 SHA 和一次性发布观察应保留在带日期的验证记录或运行快照中，不应成为长期默认发布或回滚目标。
