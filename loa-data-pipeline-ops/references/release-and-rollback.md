# 发布与回滚

使用本快照前，先读取当前组件知识和 workflow。“如何发布？”或“可以发布吗？”之类的请求只是咨询，不代表授权合并或触发 workflow。

## 授权状态

修改生产状态的工作应遵循以下状态序列：

```text
READ_ONLY_DIAGNOSIS -> PLAN -> AWAIT_AUTHORIZATION -> ONE_MUTATION -> VERIFY -> CLOSE or NEW_AUTHORIZATION
```

执行前，提供包含以下内容的 Go/No-Go 摘要：

- 组件和环境；
- 准确操作及其引发的自动触发行为；
- PR 和完整 SHA，或 workflow run ID 和 attempt；
- 目标服务器/服务；
- 预期中断/数据影响和时间窗口；
- 验证范围；
- 已知良好回滚目标和触发条件。

必须为该操作取得明确授权。授权不延续到后续发布、其他组件、Gateway `test` 到 `main`、回滚、重启、重放或数据修复。只有当全部目标细节和停止条件均已明确时，“如果 readiness 条件 X 失败，则回滚到已核验的 run Y/SHA Z”这类有界预授权才可使用。

授权必须在披露当前影响和能力差异之后取得。如果 preflight 发现新风险——例如回滚会移除告警能力——此前的“直接执行”请求不再覆盖该操作；应提供更新后的 Go/No-Go，并取得知情确认。

使用仓库中经过评审的 PR/merge 路径和已配置的 required check。绝不绕过 branch protection、启用 auto-merge、直接推送生产分支、force-push、改写生产历史，或把 `git reset --hard` 用作发布/回滚机制。

## 通用 preflight

1. 刷新远端 refs 并检查当前 worktree。保留无关的用户改动；如果改动重叠则停止。
2. 记录权威远端分支和完整目标 SHA。
3. 检查该 SHA 对应的 workflow/deploy script；在不打印配置值的前提下，核验 event trigger、checkout 行为、目标环境/服务、测试、readiness check、concurrency 和当前凭据配置键名称。
4. 确认同一目标没有未完成的部署。
5. 根据实际日志选择已知良好兜底：环境、checkout SHA、时间、run 结果和业务适用性；不能只看绿色图标。
6. 运行适当的本地测试/构建，并说明其未覆盖哪些外部系统。
7. 在考虑重启或回滚前，保留故障/发布时间线。

## Crawler 发布

- 常规生产发布：将已批准的 PR 合并到 `prod`；合并会自动触发 GitHub Actions。
- 带 `environment=prod` 的 `workflow_dispatch` 是已核验的同 SHA 重新部署/特殊操作入口，但仍会重启唯一的生产环境。
- 绝不部署历史 `test` 或 `uat` 目标。
- 重启前，尽可能要求人工操作员检查 `/api/monitoring/status`、active live connection 和进行中的 archive flush。如果无法检查，应停止；只有用户明确接受已记录的中断/数据风险时才可继续。
- 预期 workflow 阶段：Java 17 Maven test、package、SSH setup、release sync、service restart 和本机 health request。

Crawler 验证层级：

- 构建：tests 和 package 成功。
- 进程：sync、`loa-global-crawler.service` restart、active state 和 health 均成功。
- 组件：target/probe progression、Euler 行为和 live connection 行为符合预期。
- 数据路径：TOS parts/final manifest、准确的 Legacy `manifestPath`、Gateway 消费、PostgreSQL/下游结果和 duplicate-session 检查均成功。

## Crawler 回滚

已核验的机制是 GitHub deployment-style 回滚：

1. 选择历史上成功的生产 run，且其日志能证明所需 checkout SHA 和 health 结果。
2. 选择前，将旧 commit 与当前生产版本对比。特别是 2026-08-19 的历史 run `32033664076` 早于 2026-08-21 的 Crawler 告警发布；现在使用它可能移除后续能力，绝不能把它作为长期默认目标。
3. 展示 run ID/attempt/SHA/能力差异并取得授权。
4. 通过 GitHub Actions UI 或 API rerun。
5. rerun 前立即查询当前 run 状态；随后记录并监控新建的 attempt，而不是较早的 attempt。
6. 核验新 attempt、实际 checkout SHA、build、sync、restart，以及所需的组件/数据检查。

workflow 会覆盖 JAR，且不保留 previous-JAR 备份。这是 rebuild/redeploy，不是逐字节恢复。如果 restart/health 失败，新 JAR 可能已经安装；必须停止并确认实际远端状态，再采取其他操作。

## Gateway 晋级与发布

常规晋级顺序为 `dev -> test -> main`，包含两个独立发布关口：

1. 刷新并比较 `origin/dev`、`origin/test` 和 `origin/main`。
2. 执行混合版本兼容性评审。如果 diff 改变 MQ contract/filtering、ACK/NACK、retry/DLQ、manifest/part 语义、TOS identity、幂等性、event mapping、transaction/dual-schema 写入或破坏性数据库要求，应停止常规流程。
3. 取得可能影响生产的明确授权后，合并 `dev -> test`；记录 deployment run/SHA，并核验 readiness 及约定的观察/数据样本。
4. 停止并进行新的 `main` Go/No-Go。`test` 部署成功后不得自动继续。只有当预先约定的两阶段授权绑定了两个 PR/完整 SHA、test 观察指标和持续时间、各阶段的兜底方案、准确的 main 进入条件及每个阶段的停止条件时，该授权才可使用；否则必须重新取得授权。
5. 取得授权后，合并 `test -> main`；再次记录并核验。

如果 `test` 启动失败，旧 `main` 进程可保障可用性，但无法撤销 `test` 已 ACK 的消息或已写入的数据行。

Gateway workflow readiness 会检查带版本的 startup marker、已配置的 PostgreSQL/table 访问、手动 HTTP listener 和 RabbitMQ consumer 启动。它不能证明 TOS 读取、事件插入、user/avatar 处理、DLQ 行为或 Fan Radar 输出。

## Gateway 回滚

必须区分以下两种机制：

- **Deployment readiness 失败：** 等待 workflow 到达终态，再核验远端脚本是否恢复 `.previous` binary 和 `.env`，并成功重启旧版本。自动恢复仍在进行时，不得并发触发另一个 rollback run。
- **操作员版本回滚：** 选择已核验的已知良好 commit/run，说明混合 consumer 及已处理数据的后果，取得授权后通过 GitHub UI/API 触发已知良好部署，并核验 run/SHA/version/readiness/data。

两种机制都不能撤销已 ACK 的消息或已提交的 PostgreSQL/TOS 数据。服务恢复和现有数据修复是两项独立任务，必须分别取得授权。

部署/readiness 失败绝不能成为自动重放条件，即使用户提前给出笼统指示。只有故障发生并完成独立诊断后，才能建立新的重放关口。在准确失败消息、失败原因、部分写入状态、幂等边界、批次/停止限制和独立授权全部确认前，不得重放 queue 或 DLQ。

## 完成记录

记录以下内容：

- 请求结果和影响范围；
- 目标分支/完整 SHA 和服务器/服务；
- PR/run ID/attempt 和实际 checkout SHA；
- 自动执行和人工执行的操作；
- 静态、run、运行时和数据路径层级的证据；
- 已准确证明的最高结论层级；
- 已使用或保留的回滚目标；
- 尚未解决的数据后果和下一负责人/操作。
