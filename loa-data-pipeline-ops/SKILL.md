---
name: loa-data-pipeline-ops
description: 运维、发布、回滚和诊断 LOA Crawler-to-Gateway-to-Agent-Lite 数据链路及 OpenCreators API 入口迁移。适用于 loa-glabal-crawler、loa-data-gateway、loa_agent_lite、loa-mcp 的部署和告警，BytePlus 运行状态/日志、RabbitMQ/TOS/PostgreSQL、Fan Radar 数据路径，以及 OpenCreators/BattleMe BaseURL、域名、`/api` 前缀、Token 校验或 ALB 502 排障；不适用于无关的 LOA 应用层工作。
---

# LOA 数据链路运维

支持人和 AI 安全协作接管 `loa-glabal-crawler`、`loa-data-gateway`、`loa_agent_lite`，以及它们依赖的 RabbitMQ、TOS、PostgreSQL、Redis、EulerStream、ECS 和 Fan Radar 数据路径。涉及 API 入口迁移和上游 502 时，也覆盖 `loa-mcp`、OpenCreators/BattleMe 后端及相关消费者的配置核验。

只处理用户当前提出的请求。不要把故障咨询扩展为重新设计，也不要把发布请求扩展为更广泛的生产维护。

## 仓库来源与定位

本 Skill 面向以下 GitHub 仓库的本地 clone，不依赖固定用户名或目录结构：

- Crawler：[Lighthunter-PTE-ltd/loa-glabal-crawler](https://github.com/Lighthunter-PTE-ltd/loa-glabal-crawler)
- Gateway：[Lighthunter-PTE-ltd/loa-data-gateway](https://github.com/Lighthunter-PTE-ltd/loa-data-gateway)
- Agent Lite / Fan Radar：[Lighthunter-PTE-ltd/loa_agent_lite](https://github.com/Lighthunter-PTE-ltd/loa_agent_lite)
- MCP：[Lighthunter-PTE-ltd/loa-mcp](https://github.com/Lighthunter-PTE-ltd/loa-mcp)
- OpenCreators 后端：[Lighthunter-PTE-ltd/opencreators_backend](https://github.com/Lighthunter-PTE-ltd/opencreators_backend)
- Legacy BattleMe 后端：[Lighthunter-PTE-ltd/battleme_backend](https://github.com/Lighthunter-PTE-ltd/battleme_backend)
- API 消费者：[Lighthunter-PTE-ltd/opencreators_app](https://github.com/Lighthunter-PTE-ltd/opencreators_app)、[Lighthunter-PTE-ltd/loa-im](https://github.com/Lighthunter-PTE-ltd/loa-im)

`opencreators_app` 和 `loa-im` 只在 API 入口、回调或 Token 校验迁移范围内处理；其他应用功能仍不属于本 Skill。

需要读取代码或 workflow 时，先在当前 workspace 中定位 clone，并用 `git remote get-url origin` 核对仓库身份；HTTPS 与 SSH remote 视为同一仓库。不要假定任何固定绝对路径，也不要假定仓库与 Skill 相邻。找不到 clone 时，说明缺失哪个仓库：纯说明任务可继续使用随附快照；需要当前代码证据时，应让用户提供/clone 仓库或明确授权在其指定目录 clone，不得静默改用另一个同名目录。

## 加载当前知识并按任务路由

随附 `references/` 是可移植的运维知识快照，不要求外部 `loa-data-pipeline-ops` 目录。仅按当前模式读取必要的参考资料：

- 环境、分支、主机、端口、服务或日志位置：读取 [references/environment.md](references/environment.md)。
- 发布或版本回滚：读取 [references/environment.md](references/environment.md) 和 [references/deployment-control-plane.md](references/deployment-control-plane.md)，再读取目标 SHA 对应的当前 workflow、部署脚本和近期 run；不要从参考资料复制执行步骤。
- Crawler 告警、采集、TOS、MQ 发布或 Crawler 日志：读取 [references/crawler-diagnosis.md](references/crawler-diagnosis.md)。
- Gateway MQ、TOS 导入、PostgreSQL、DLQ、用户/头像、手动导入、Gateway 日志或 BytePlus TLS/LogCollector：读取 [references/gateway-diagnosis.md](references/gateway-diagnosis.md)。
- Agent Lite Worker/Gateway、应用日志、journald、BytePlus TLS/LogCollector 或 Agent Lite 告警：读取 [references/agent-lite-diagnosis.md](references/agent-lite-diagnosis.md)。
- Fan Radar 数据缺失/错误，或故障组件未知：读取 [references/end-to-end-diagnosis.md](references/end-to-end-diagnosis.md)，先定位故障边界，再读取相关组件的参考资料。
- OpenCreators/BattleMe API 域名、BaseURL、`/api` 前缀、Token 校验、MCP 上游 502 或 ALB host 路由：读取 [references/opencreators-api-domain-migration-2026-08-27.md](references/opencreators-api-domain-migration-2026-08-27.md)。

只有精简参考不足以回答当前问题时，才进一步读取详细材料：

- Crawler 完整职责、数据契约或历史交接：按需读取 [references/crawler/knowledge-base.md](references/crawler/knowledge-base.md)、[references/crawler/external-handover.md](references/crawler/external-handover.md) 或 [references/crawler/live-end-mq-contract.md](references/crawler/live-end-mq-contract.md)。
- Crawler TLS/Codex 诊断架构或 2026-08-19 发布实证：读取 [references/crawler/tls-incident-architecture.md](references/crawler/tls-incident-architecture.md) 或 [references/crawler/release-validation-2026-08-19.md](references/crawler/release-validation-2026-08-19.md)。
- Gateway 完整职责、部署语义或 TLS 人工实施：读取 [references/gateway/knowledge-base.md](references/gateway/knowledge-base.md) 或 [references/gateway/tls-logcollector-guide.md](references/gateway/tls-logcollector-guide.md)。
- Agent Lite 完整职责、部署语义、历史运行快照或 TLS 人工实施：按需读取 [references/agent-lite/knowledge-base.md](references/agent-lite/knowledge-base.md)、[references/agent-lite/runtime-snapshot-2026-08-22.md](references/agent-lite/runtime-snapshot-2026-08-22.md) 或 [references/agent-lite/tls-logcollector-guide.md](references/agent-lite/tls-logcollector-guide.md)。TLS 实施涉及的已审计安装文件位于 [assets/agent-lite-tls/](assets/agent-lite-tls/)；使用前仍应核对当前主机与 unit 状态并重新取得生产变更授权。

不要默认加载全部参考资料。随附参考资料只是运维兜底信息，不能证明 GitHub 或云端当前状态。如果当前仓库/工作区证据与参考资料冲突，应明确报告；若冲突涉及安全，应在任何变更前停止，不得静默选择其中一个值。

## 请求分类

选择一个主要模式并简要说明：

- **说明/评估：** 根据代码、文档和只读状态作答，不做任何变更。
- **诊断：** 收集只读证据并定位故障边界。除非用户明确要求，否则不实施修复。
- **日志协作：** 为人工操作员生成范围严格的只读命令集，然后只分析返回的脱敏输出。
- **发布：** 在安全范围内自动准备和验证；只有获得明确授权后，才执行指定的生产变更。
- **回滚/恢复：** 以只读方式确定已知良好目标及恢复后果；只有获得明确授权后才执行。
- **代码变更：** 先检查并讨论兼容性。除非用户明确要求，否则不编辑；不得借助此运维技能绕过尚未解决的设计决策。

默认将“如何发布？”“可以发布吗？”及同类问题视为说明/评估。仅为回答一般流程问题，不要刷新远端、构建、合并或触发外部工作；只有确实需要当前证据且用户要求核验时才可执行相应检查。

尽可能从本地仓库或 GitHub 确认组件、目标分支、workflow 和 run 状态。只有缺失的选择会实质改变或扩大操作范围时，才向用户询问。

## 自动执行与人工协作

可自动执行范围内的安全工作：

- 检查文件、分支、diff、workflow、run 历史和 worktree 状态；
- 当前核验确有需要时，获取远端状态；该操作对远端/生产系统只读，但可能更新本地 Git 元数据；
- 运行不会访问生产系统的本地测试/构建；
- 执行 GitHub 只读查询；
- 分析脱敏日志，并准备准确的诊断、发布或恢复步骤。

如果所需工具和权限均可用，且指定操作已获授权，就执行并验证结果。如果访问必须由人工完成或当前不可用，应提供准确的 UI/命令说明、所需返回字段、脱敏指引、预期信号和停止条件。

每次修改生产状态前都必须即时取得明确授权，包括 merge/push、workflow dispatch/rerun、restart/stop、回滚、RabbitMQ 干预或 DLQ 重放、手动 manifest 导入、数据库/TOS/Redis 写入以及云资源变更。

一项操作的授权不覆盖相邻操作。发布不代表授权重放，诊断不代表授权修复，回滚也不代表授权数据修复。

授权必须建立在充分知情的基础上，并绑定具体目标。最终 Go/No-Go 前，应展示组件、环境、准确的 PR/SHA 或 run/attempt、影响、验证方式、兜底方案和停止条件。“全部执行”之类的笼统表述，或在披露新发现的能力缺失/生产风险前提出的执行请求，都不构成对该变化风险的授权。不得绕过受保护分支检查、直接推送生产分支，或为图方便启用 auto-merge。

生产日志访问由人工把关：必须由人进入 BytePlus 并使用获批密钥。绝不索取、存储、回显或代管该密钥。只提供命令和结果解读，不假设 AI 能直接访问生产主机。

## 不可违背的约束

- 工程发布和版本回滚只能通过目标仓库的 GitHub Actions 完成。不得用本机脚本、直接 SSH、手工复制制品或通过 SSH 直接重启服务来替代缺失的 Action 能力；如果当前 workflow 不能把操作绑定到准确的目标 SHA，应停止并报告控制面缺口。
- Crawler 没有可用的 test/UAT 环境。不得仅因 YAML 中仍保留历史 `test`/`uat` workflow 目标就进行部署。
- Gateway `test` 并不隔离。它与 `main` 共用生产服务器和依赖，并竞争消费同一 RabbitMQ 队列；任何 `test` 部署都按可能影响生产处理。
- Gateway `dev -> test -> main` 只保障进程可用性。如果混合版本可能改变 MQ/TOS/数据库契约、ACK/NACK、重试/DLQ、过滤、幂等或写入语义，应停止并先完成兼容性/迁移决策。
- 绝不能把部署/readiness 失败配置为 RabbitMQ/DLQ 自动重放条件，即使用户提前提出此要求。失败发生后，应先恢复并核验服务状态、诊断准确的消息/数据状态；任何重放或历史数据修复都必须重新进入证据与授权关口。
- 绿色 GitHub Action 或 `health=UP` 只能证明其实际覆盖的检查。构建成功、进程部署成功和数据路径成功必须分别得出结论。
- 绝不复述在 profile、workflow 日志、事件日志或错误中发现的凭据或敏感值。

## 操作流程

1. 明确组件、模式、目标环境、时间窗口、症状/操作和预期结果。
2. 更新只读事实：worktree、权威远端分支/SHA、workflow、近期 run 状态和当前知识。
3. 将证据标记为仓库/静态事实、本地测试、GitHub run、服务器/运行时、数据路径或用户确认的运维事实。
4. 说明影响范围，并区分自动执行与人工执行的内容。
5. 完成安全检查。变更前展示准确目标/操作、已知良好兜底、验证方式和停止条件，再取得授权。
6. 只验证到用户要求且证据实际支持的层级：构建/测试、已部署进程/readiness、组件行为；需要时再验证端到端数据路径。
7. 提供简洁的交接记录：结果、目标环境/分支/SHA、操作或命令、适用时的证据及 run ID/attempt、已证明的结论层级、剩余未知项，以及下一项安全操作/负责人。

## 停止条件

遇到以下情况时，在任何变更前停止并请求用户决定：

- 分支到环境的映射与当前证据冲突；
- worktree 中存在与本次工作重叠的用户改动；
- 生产授权、操作或目标含糊不清；
- Crawler 请求假定存在安全的非生产环境；
- Gateway 变更可能造成混合版本数据语义；
- 回滚目标无法关联到已核验的提交和成功 run，或当前 workflow 不能检出该准确 SHA；
- 所需证据会暴露密钥，或要求 AI 代管生产密钥；
- 诊断进入重放或数据修复阶段：必须重新进入证据与授权关口；若架构决策尚未解决，则另行停止。
