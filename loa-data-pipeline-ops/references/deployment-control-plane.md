# GitHub Actions 发布控制面

GitHub Actions 是 Crawler、Gateway、Agent Lite 和 OC Flow Guard 四个工程发布和版本回滚的唯一执行入口。本文件只记录控制面映射和无法从 workflow 单独推导的边界；当前目标 SHA 对应的 workflow、部署脚本、GitHub 配置和 run 才是执行事实源。

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
- `dev` 是受保护的默认开发分支，不触发环境部署。`Deploy on merge` 当前直接监听 `test`、`main` 的 `push`；受保护分支 PR merge 是正常晋级方式，但 workflow 不再读取 PR payload。
- `test` 对应 `lc-oc-test-lite`，`main` 对应 `lc-oc-prod`。Workflow 使用 `github.ref_name` 与 `github.sha`，要求目标 SHA 是 40 位十六进制值，checkout 后再次核对实际 HEAD，再执行 check、test、Leo runtime smoke、制品构建和部署。
- GitHub Environments 使用 custom branch policy：`lc-oc-test-lite` 只接受 `test`，`lc-oc-prod` 只接受 `main`。两者在 2026-09-01 核验时只有 branch policy，没有 required reviewer；分支限制不能替代人工批准门禁。
- Test/Prod 的 provider API keys 使用各自 Environment 中无环境后缀的 `ATLAS_API_KEY`、`MEM0_API_KEY`、`SANDBASE_API_KEY`、`VERCEL_API_KEY`；六个 Agent/Live Recap/Translation model routes 和 `DEPLOY_*` 也使用 Environment Variables。Repository Variables 只保留 `SANDBASE_BASE_URL`、`ATLASCLOUD_BASE_URL`、`VERCEL_BASE_URL`。不得恢复带 `_TEST` / `_PROD` 后缀的运行时密钥、Repository model fallback、硬编码测试地址或 `LC_OC_PROD_*`。
- SSH 用户/私钥仍由组织级 Secrets 按 `TARGET_BRANCH` 选择。Test 只需要 `DEPLOY_A_*` 并部署 Worker + Gateway + Gateway B；Prod 还要求 `DEPLOY_B_*`，先部署 A 的 Worker + Gateway，再部署 B 的 Gateway。环境选择、凭据选择、SSH 配置和部署目标必须使用同一个分支判定。
- 配置经 CI 非空/route 校验后，以 NUL 分隔记录通过 stdin 送到服务器；部署脚本再次校验并以 `0600` 权限原子更新 `.env`。Gateway health 后还会执行真实翻译 smoke。完整合同和 2026-09-01 证据见 [agent-lite/configuration-migration-2026-09-01.md](agent-lite/configuration-migration-2026-09-01.md)。
- 生产按 `prod-a` 后 `prod-b` 串行部署，不是跨主机事务。单机自动 rollback 会恢复 release 和 `.env`、重新安装依赖、重启并复查 Gateway health，但不会重跑翻译 smoke 或核验 Worker；不得把它视为完整生产回滚。
- `.github/workflows/release.yml` 的手工 pre-release 只允许从 `test` 运行；stable release 仍由符合 `vX.Y.Z` 的 tag 触发。Release 与环境部署是不同控制面，绿色 Release 不证明测试或生产服务器已更新。
- 2026-09-01 的配置迁移已按 `dev -> test -> main` 推进。Test run `33481379194` 部署 `8b507550...`，Prod run `33482168214` 部署 `ffb8b882...`，两者 conclusion 均为 `success`；这些结果仍只能证明 workflow 实际覆盖的构建、部署、health 与翻译 smoke。

## OC Flow Guard

- 仓库：`Lighthunter-PTE-ltd/oc-flow-guard`；控制面入口：`.github/workflows/deploy-main.yml`、`scripts/deploy-main.sh` 和 `scripts/deploy-release.py`。
- 平台只有一个部署实例。`dev` 不触发部署；常规 `main` push 触发 `Deploy platform main`，受限 `workflow_dispatch` 也只在 `main` ref 执行。这个控制面同时展示业务 `test`/`prod`，不能把业务环境选择解释为两套平台部署。
- Workflow 固定 `github.sha` checkout 并复核 HEAD，使用 Node `24.20.0` / npm `11.19.0`，执行依赖安装、typecheck、build、Python 部署安全测试、Chromium/Node 隔离测试和生产依赖裁剪，随后才进入部署。concurrency 为 `oc-flow-guard-main` 且 `cancel-in-progress=false`。
- 部署 job 使用 `loa-self-hosted` runner 和组织 UAT/Test SSH secrets，把摘要发布包送到固定目标 `172.31.0.2`；该 SSH 是 Action 内部的交付通道，不授权操作员绕过 Action 直接发布、复制 release 或重启服务。
- 远端活动根固定为 `/www/typescript-server/oc-flow-guard`。`scripts/deploy-release.py` 校验归档路径、package SHA-256、`dist/release.json`、锁文件、Node 版本和 schema 2；停止执行器后若存在 `journal.json` 会拒绝切换，随后停控制服务、核对 cgroup、执行数据库 check、原子更新 `current`，最后要求双服务 active 和本次启动后的新鲜执行器心跳。
- `workflow_dispatch` 的 `migrate_auth_layout`/`proxy_cidr` 是 2026-09-01 一次性 schema/auth/TypeScript 根迁移入口。迁移和最终旧登录清理已经完成；普通发布不得再次设置该输入，也不得恢复旧 `/opt/oc-flow-guard` 或 schema 1。
- 当前浏览器入口依赖既有域名服务鉴权。当前部署脚本覆盖停服数据库 check、systemd active 与本次启动后的执行器心跳，不直接请求公开 `/readyz`，也不持有浏览器会话；规范入口未登录/登录行为、公开健康和路径映射必须作为独立入口证据。
- 2026-09-01 GitHub 只读核验：`main@943aee606d2d7c9a8fa6fdee312f980979e97e78` 的 run `33482448536` / attempt 1 为 `success`，deploy job `99774875185` 成功。该 run 是当日最新发布实证；操作前仍要查询更新的 main/run 和主机活动 `deployment.json`。
- 当前 workflow 没有“输入任意历史 SHA 并部署”的常规回滚入口。回滚候选必须先证明是已验证的无登录 schema 2 release，并能由受保护分支/Action 精确检出；若做不到，应报告控制面缺口，不得改用直接 SSH 切 `current`。
- 发布不能回滚 SQLite 中已经保存的部署/运行/进度，也不能撤销已经执行的业务副作用。恢复旧数据库副本是独立停服恢复任务，需重新评估 restore quarantine、执行器 journal、绑定启用边界和 GitHub 补查后果。

## 快照与历史证据

上述日期信息用于发现配置漂移，不替代当前 GitHub 查询。具体历史 run ID、旧 SHA 和一次性发布观察应保留在带日期的验证记录或运行快照中，不应成为长期默认发布或回滚目标。
