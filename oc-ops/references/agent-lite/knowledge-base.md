# Agent Lite 接管知识底稿

更新日期：2026-09-01

本文整理 `loa_agent_lite` 的完整工程职责、数据依赖、发布方式、运行边界和故障定位入口。主体证据来自 2026-08-22 的仓库、GitHub Actions 和服务器只读快照，2026-08-28 补充分支/访问控制面，2026-09-01 补充模型、密钥、部署目标配置归一化和 test/prod 发布验证。历史 run、旧分支名和原操作者工作区只描述当时时点；当前发布映射以 [deployment-control-plane.md](../deployment-control-plane.md) 为准，访问绑定以 [access-channel.md](../access-channel.md) 为准，配置迁移实证见 [configuration-migration-2026-09-01.md](configuration-migration-2026-09-01.md)。

## 1. 资料、仓库身份与证据基线

代码仓库：`Lighthunter-PTE-ltd/loa_agent_lite`。

2026-08-22 原操作者执行 `git fetch origin --prune` 并核验的历史基线：

- `origin/main@d2fcbf50ea970d6e778a6b8cdab4ec8997f95b81`
- `origin/prod@47405c886270ce814836698d0a2688b9ed9d81af`
- 当时 `origin/prod` 是 `origin/main` 的直接祖先，`main` 比 `prod` 多一个 `d2fcbf5` 提交；这些旧分支名已被 2026-08-28 的分支迁移取代。
- 原操作者本地 `main@263c5466926b01b6c6801e5d1528cd808bc5816a` 工作区干净，但比当时 `origin/main` 落后 20 个提交。该信息不描述其他使用者的 clone，也不得作为当前分支状态。

2026-08-22 历史证据来源：

1. `origin/main` / `origin/prod` 的代码、README、文档和 workflow。
2. `.github/workflows/release.yml`、`deploy-prerelease.yml`、`deploy-production.yml`。
3. `scripts/build-release-artifacts.sh` 和 `scripts/deploy-release-on-server.sh`。
4. 2026-08-22 只读查询到的 GitHub Actions run 和步骤结果。
5. `runtime-snapshot-2026-08-22.md` 中的服务器 systemd、监听、版本摘要和日志配置快照。

本文严格区分：

- **静态事实：** 仓库声明和代码预期行为。
- **GitHub run 实证：** 某 SHA 的 CI、制品构建和 workflow 部署步骤确实成功。
- **运行时事实：** 服务器、systemd、进程、监听、非敏感配置元数据和版本摘要的时间点快照；已取得的范围以 `runtime-snapshot-2026-08-22.md` 为准。
- **数据路径事实：** PostgreSQL、RabbitMQ、TOS、LOA API、模型和客户端的真实行为；本轮尚未端到端核验。

## 2. 工程定位与完整接管范围

Agent Lite 不是单一 Fan Radar Worker，而是基于 Bun 和 Mastra 的完整 Agent 服务。接管范围包括：

1. `apps/realtime-gateway`：HTTP IM 接入、IM inbox/outbox 处理、Agent 对话、Fan Radar 客户端 API、内部 dashboard、报告分享、翻译和运维 HTTP 接口。
2. `apps/worker`：用户生命周期 RabbitMQ 消费、直播复盘、Fan Radar materialization、memory delivery、Agent 失败告警和模型 provider 健康探测。
3. `apps/dashboard`：由 Gateway 托管的内部单文件 dashboard。
4. `packages/agent-runtime`：Mastra Agent、模型路由和 fallback、工具、RAG、memory 与报告生成。
5. `packages/domain` / `contracts` / `i18n` / `prompting`：业务规则、跨层合同、多语言固定文案和 prompt。
6. `packages/infra`：PostgreSQL、Redis、RabbitMQ、LOA backend、message-service、TOS、Mem0、模型 provider 和安全服务适配。
7. `ops/bedrock-path-monitor`：独立的 Bedrock 网络/模型路径探针；它不启动 Agent Lite 应用。

Fan Radar 是 Crawler → Gateway → PostgreSQL ODS 后的数据链路重点，但不应成为裁剪 Agent Lite 其他职责的理由。

## 3. 运行组件与主要入口

### Realtime Gateway

代码默认监听 `127.0.0.1:18765`，可由 `REALTIME_HOST`、`REALTIME_PORT` 覆盖。2026-08-22 运行时快照确认测试和生产实际均监听 `0.0.0.0`；主要入口：

- `POST /agent/v1/internal/message/send`：可信内网 HTTP IM 入口。请求写入 PostgreSQL inbox 后返回 `202`；相同 `tenantId + mid` 重复请求返回 `200`。
- `/agent/v1/me/fan-radar/*`：当前认证用户的 Fan Radar 读写接口。
- `/dashboard.html` 和 `/api/*`：内部用户、会话、Agent audit、报告、分享和翻译入口。
- `GET /health`、`GET /healthz`：进程存活检查。
- `/admin/status`、`POST /admin/drain`、`POST /admin/resume`：发布期 drain 控制。

安全边界：

- HTTP IM 和内部 dashboard 没有独立的终端用户认证边界，必须由反向代理/网络层限制在可信内部网络。
- `REALTIME_ADMIN_TOKEN` 未配置时，admin 接口不要求 token；不能在未核验网络暴露面的情况下把它视为安全入口。
- `/health` 只返回 Gateway 进程存活信息，不检查 PostgreSQL、Redis、RabbitMQ、LOA API、message-service、模型、Worker 或 Fan Radar 数据路径。
- 多 Gateway 实例使用 PostgreSQL lease 分配 IM inbox/outbox，并使用 Redis session lock 保护同一会话。
- IM 失败默认持久化后重试；`IM_HTTP_MAX_ATTEMPTS=0` 表示没有次数上限。明确的部分 4xx 和达到非零最大次数后会进入 PostgreSQL 中的 dead-letter 状态，而不是 RabbitMQ DLQ。

### Worker

Worker 启动并编排：

- 用户生命周期 RabbitMQ consumer；
- 每用户时区的定时直播复盘；
- 开启后的 Fan Radar materializer；
- Mem0 delivery maintenance；
- Agent 失败 Feishu 告警调度；
- 模型 provider health probe 和恢复告警。

Worker 没有仓库内的 HTTP health endpoint。部署脚本会重启 Worker，但不会对 Worker 的启动完成、调度器状态或依赖可用性做独立 readiness 检查。

当前入口文件虽然返回可执行 `stop()` 的 runtime handle，但直接启动路径只调用 `await startWorker()`；仓库中未看到把 `SIGTERM`/`SIGINT` 接到该 `stop()` 的代码。实际 systemd 停止语义和长任务中断行为仍需结合线上 unit 与日志核验。

## 4. 外部依赖与数据存储

### Runtime PostgreSQL

`DATABASE_URL` 用于 Agent Lite 自身状态。`LOA_DB_TABLE_PREFIX` 隔离环境，仓库文档规定正式环境使用 `prod_`。主要数据包括：

- 用户 profile 和删除 tombstone；
- chat session/event；
- Agent run/tool audit 和告警 delivery；
- IM conversation/inbox/outbox；
-直播复盘报告和 benchmark；
- Mem0 delivery/scope registry；
- Fan Radar Skip/Copy 交互和报告分享链接。

多数运行时表通过 `ensureLoaPostgresSchema` 按需执行 `create table if not exists` / `alter table` / `create index`。因此运行账号不仅需要读写数据，还可能需要 DDL 权限。绿色 Gateway health 不证明这些权限满足。

### Live Recap / Fan Radar PostgreSQL

`LIVE_RECAP_DATABASE_URL` 必须与 Runtime `DATABASE_URL` 分开理解。`LIVE_RECAP_SCHEMA` 只允许：

- 测试：`test_liveonair_tiktok`
- 正式：`prod_liveonair_tiktok`

Agent Lite 从该 schema 的 `ods_tiktok_live_event_detail` 读取 Data Gateway 已导入事件。Fan Radar 报告写入同 schema 的 `fan_radar_reports`。该业务表由数据库负责人提供，Agent Lite 不创建/迁移它；运行账号需具备所需 SELECT/INSERT/UPDATE/DELETE 权限。

### 其他依赖

- Redis：跨 Gateway session lock、限流和缓存。
- RabbitMQ：用户生命周期消费，以及直播复盘通知发布。
- LOA backend：token 校验、Profile、头像签名和业务 API。
- message-service：IM 出站投递。
- 模型 provider：当前统一 route 支持 SandBase、AtlasCloud、Vercel 及配置的 fallback；Bedrock adapter/path monitor 仍属于独立代码与观测能力，不能据此推断当前 Agent/Translation 路由使用 Bedrock。
- Mem0：可选长期记忆；关闭后 Chat Agent 仍使用 Mastra PostgreSQL Memory。
- TOS：直播复盘 HTML 发布；当前用户删除时由后端负责对象删除。
- LOA MCP：Creator 商品目录等工具数据。
- safety guard：用户消息安全分类。

仓库当前 RabbitMQ 配置代码中存在硬编码凭据字面量。知识库不记录值，也不得在诊断输出中复述；这应作为独立凭据治理和轮换风险处理。

### 模型、密钥与部署配置所有权

- Agent、Live Recap 和 Translation 的六个 model route 使用各自 test/prod GitHub Environment Variables，统一格式为 `<Provider>-<model-id>`；Repository 层不再保留同名 model Variables。
- Provider API keys 和 `MEM0_API_KEY` 使用无环境后缀的 GitHub Environment Secrets。Provider Base URL 由两个环境共享，仍保留为 Repository Variables。
- Translation 与 Agent 复用同一 route descriptor 和 Provider connection 解析；Translation 使用 Chat Completions，Agent/Live Recap 使用 Responses。不要恢复独立 Translation provider/key/base URL 解析。
- Test/Prod 主机地址和端口使用 `DEPLOY_*` Environment Variables；SSH 用户和私钥仍为组织级 Secrets。
- 部署只按固定键集合把配置写入 `.env`，缺失 Environment 值时应失败，不得恢复 Repository fallback 或带环境后缀的旧键。准确键名、约束和 2026-09-01 验证见 [configuration-migration-2026-09-01.md](configuration-migration-2026-09-01.md)。

## 5. Fan Radar 数据路径与当前静态语义

数据路径：

```text
Crawler
  -> TOS / Legacy live.ended MQ
  -> Data Gateway
  -> prod/test ODS ods_tiktok_live_event_detail
  -> Agent Lite Worker
  -> fan_radar_reports
  -> Agent Gateway 当前用户 API
  -> LOA App / H5
```

主要静态关口：

- 普通用户按 `loa_user_guid = hostGuid` 匹配 ODS；运营测试用户按 Profile 中的 TikTok `streamer_id` 匹配。
- Profile 缺少时区的用户不会进入定时 Worker 用户列表，因为查询只选择非空时区。
- 日内 materializer 会过滤 `isOpsTest=true` 用户；次日定时复盘链路仍可以按 `streamer_id` 为运营测试用户生成 Fan Radar。
- 日内 materializer 只把包含 `SYSTEM_LIVE_ENDED` 的 room 视为完成场次；按 Profile 时区的本地自然日扫描。
- 内存 checkpoint 使用 `hostGuid + summaryDate + completedStreamCount`。Worker 重启后会重新扫描；报告 upsert 通过较新的 `generated_at` 防止旧结果覆盖新结果。
- 单个 creator/date 的 Workflow 先加载 ODS 数据，执行确定性分类和排序，再逐粉丝生成消息，最后完整校验并原子 upsert `fan_radar_reports`。
- `fan_radar_reports` 按 `(host_guid, summary_date)` 唯一；Agent Lite 不迁移该表。
- Gateway 使用认证 token 解析当前用户 GUID，不接受客户端指定 `hostGuid`。
- `/latest` 优先当天报告，再回退最新历史；完全没有报告时返回 `200` 和结构完整的当天空报告，不再返回 `404`。
- 指定日期不存在时同样返回 `200` 空报告；`404 report_not_found` 主要用于 Skip/Copy 指向不存在的已存报告。
- Profile 本地时区缺失时，Gateway 会尝试从 LOA API 刷新；刷新不可用或仍缺失时按 UTC 计算，并在请求日志中记录错误。不能再沿用“缺时区必定 403”的旧判断。
- 头像 URL 在读取时通过 LOA backend 按 object key 签名；签名失败时报告仍返回，只省略头像 URL 并记录 warning。
- Fan Radar 请求日志包含 request ID、状态、耗时、认证来源、token 哈希指纹、host GUID、日期和数量。分享日志时仍需按时间/request ID 裁剪，避免扩大用户标识符暴露。

## 6. Live Recap、通知与用户生命周期

### Live Recap

- Worker 默认每分钟扫描，在每个用户 Profile 时区的 `LIVE_RECAP_DAILY_TIME`（默认 `00:30`）之后处理上一自然日。
- 每轮单飞执行，默认最多生成 100 份报告、扫描 10,000 个用户。
- 报告事实源是 ODS；生成结果写入 Runtime PostgreSQL 的 `loa_live_recap_reports`。
- HTML 发布和通知具有独立持久化状态。已有报告但通知未发布时，后续调度会继续尝试通知。
- 后端通知使用 RabbitMQ confirm channel、持久消息和 `mandatory=true`；当前 publisher 未处理 mandatory return 事件，因此 confirm 成功仍不足以证明存在匹配路由或下游已处理。
- 模型返回 payment-required 类错误时会打开进程内 circuit，停止本轮及后续调度尝试；恢复条件和实际运行状态需结合日志核验。

### 用户生命周期

- durable queue 默认为 `loa_agent_lite.user_lifecycle`，绑定 `user.update.success` 和 `user.deleted.success`。
- Profile 更新会刷新 `loa_user_profiles` 并同步已有会话 bootstrap profile。
- 删除事件先写不可逆 GUID 摘要 tombstone，再清理聊天、审计、复盘、Fan Radar、memory 和相关状态；迟到事件不能重新创建已删除用户。
- handler 失败默认无限重试，通过持久 retry queue、TTL 和 confirm 后 ACK 原消息。
- 无法解码的消息默认 NACK 且不 requeue；仓库没有为该 queue 声明专用 DLQ。除非 broker policy 另有配置，否则不能假设 malformed 消息可恢复。

## 7. 告警与观测边界

### Agent 失败告警

- 仅配置 `AGENT_ALERT_FEISHU_WEBHOOK_URL` 后启用。
- Worker 从 Runtime PostgreSQL 中扫描最近 Agent run 失败，默认有 5 分钟 recovery grace；同一消息/Agent 后续成功可把未发送失败标记为 recovered 并抑制。
- 默认每小时只发送一次批次，其余 pending failure 被抑制；不是逐故障可靠通知。
- Feishu 投递失败会把当前记录标为 delivery failed，并抑制其他 pending failure；不会持久重试本批告警。
- 默认投递超时 8 秒，支持签名，payload 有大小和字段长度限制。

### Provider 健康告警

- 需要 provider、模型、API key 和 Feishu webhook 才启用；默认检查当前模型 provider。
- 默认每 5 分钟做真实 inference probe，20 秒超时，10 秒以上视为 degraded，连续 2 次异常告警，连续 2 次健康发送恢复告警。
- SandBase/AtlasCloud 还可对 models endpoint 做独立检查；状态只保存在 Worker 内存中，重启后丢失 incident state。
- 探针成功只能证明指定 provider/model 路径，不证明 Agent、数据库、RAG、工具或用户请求端到端正常。

### Bedrock Path Monitor

- 独立 systemd timer 每分钟运行，不导入 Agent Lite 应用。
- JSONL 默认写入 `/var/log/loa-bedrock-path-monitor/<scenario>.jsonl`；失败证据写入 `evidence/`。
- logrotate 每日轮转、保留 30 代并压缩。
- 仓库只证明安装方式和预期路径，不证明生产两台主机已经安装、启用或使用哪些 scenario。

### BytePlus TLS 测试及生产接入状态

截至 2026-08-25，生产基础 Agent journald 采集链路已在两台节点验证：Worker 日志从 `prod-a` 进入 TLS，`[gateway] Fan Radar request` 日志从 `prod-a`、`prod-b` 均可进入 TLS。完整实施与验收步骤见 [tls-logcollector-guide.md](tls-logcollector-guide.md)：

- 保留现有 journald 入口，由独立 `loa-agent-lite-tls-export.service` 只读导出实际安装的 `loa-agent-*` units。
- 统一生成 `/var/log/loa-agent-lite/application.jsonl`，LogCollector 使用 JSON 模式；不能照抄 Crawler 的 multiline 模式。
- Test 与 Prod 使用不同 Topic/IAM；生产 A/B 使用不同 host group/rule，并注入 `node=prod-a|prod-b`。两台生产节点的 OS hostname 相同，不能只靠 hostname 区分。
- TLS 内通过 `_SYSTEMD_UNIT` 区分 Worker、Gateway、Gateway B；首期不回灌历史 journal，不采集 `.env`、数据库/MQ payload、Agent audit 表或原始用户消息文件。
- 测试节点 `lc-oc-test-lite` 已安装 exporter 与 LogCollector `2.4.2`。exporter 输出 `/var/log/loa-agent-lite/application.jsonl`；规则 `oc-agent-test-application` 写入 Project/Topic `oc-agent-test`，Topic ID 为 `294f5549-286b-42b0-b335-9c52cdf25215`，host group 为 `oc-agent-test`。
- 测试链路使用 `ap-southeast-1` 私网 endpoint `https://tls-ap-southeast-1.ibytepluses.com`；LogCollector 配置的解析目标已收紧为 `0600 root:root`。核验时 heartbeat 正常、`HarvesterNum=1`、`RuleNum=1`、成功发送 29 条、失败和丢弃为 0。
- 操作员已确认空查询、`environment:test AND node:test` 与 Worker unit 查询均有结果。该证据只证明测试日志采集和 TLS 查询链路，不证明 Agent Lite 依赖或 Fan Radar 数据路径健康。
- 生产 Region 为 `ap-southeast-1`，Project/Topic 均为 `oc-agent-prod`，Topic ID `09508bca-ee7a-4584-a7ad-0322c30f9e7c`，2 个分区、保留 7 天；A/B 使用独立 host group `oc-agent-prod-a|b` 和 rule `oc-agent-prod-a|b-application`。
- `prod-a` 的 exporter 与 LogCollector `2.4.2` 均为 active/enabled、`NRestarts=0`，heartbeat/harvester/rule/发送计数正常且失败和丢弃为 0；操作员已看到 Worker 与 Gateway Fan Radar 请求日志。
- `prod-b` 的 exporter 与 LogCollector 同样正常。早期 `HarvesterNum=0`、发送计数为 0、JSONL 为 0 bytes 的快照是当时没有触发日志的业务流量；用户随后确认 B 的 Gateway Fan Radar 请求日志可在 TLS 查询，证明基础配置正常。
- 随附 exporter systemd、shell 和 logrotate 资产位于 [`assets/agent-lite-tls/`](../../assets/agent-lite-tls/)。

### 观测盲区

- Gateway health 是浅存活检查。
- Worker 没有 readiness/health endpoint。
- 当前基础链路能采集 Worker/Gateway 实际写入 journald 的日志，但 Gateway 没有覆盖所有路由的统一 access logger；`[gateway] Fan Radar request` 只覆盖 Fan Radar 客户端 API。因此该 Topic 仍不能用于精确统计全部 A/B 请求量或替代 ALB access log。
- Worker 只在 A 上运行，所以持续、高频日志仍主要来自 A；Gateway 的正常业务日志较少，空窗口通常应先核对业务流量和日志埋点，而不是采集配置。
- Agent Feishu 告警不覆盖全部 Worker/Gateway/数据库/MQ 错误。
- 仓库没有外部主机/进程监控、队列积压告警、Fan Radar 无报告 SLO 或完整数据链路恢复通知的静态证据。

## 8. Release、测试环境和生产部署

### Release

- 2026-09-01 当前控制面中，环境部署由 `test` 或 `main` 的 `push` 触发；workflow 使用 `github.sha` 作为 `TARGET_SHA`，校验为 40 位 SHA 并在 checkout 后复核。通过受保护分支 PR merge 是正常晋级路径，但不是 workflow 的直接 event。
- 手工 pre-release 只允许从 `test` 运行；符合 `vX.Y.Z` 的 tag 仍生成 stable release。Release 与环境部署是两条独立路径，绿色 Release 不证明测试或生产节点已更新。
- 2026-08-22 的 `main` prerelease、`workflow_run` 测试部署和旧 `prod` 手工生产 workflow 只作为下文历史证据，不能作为当前入口。

### 测试环境

仓库静态资料声明：

- GitHub environment：`lc-oc-test-lite`
- Gateway 服务地址：`172.31.47.34`
- `loa-agent-worker`
- `loa-agent-gateway`：`18765`
- `loa-agent-gateway-b`：`18766`
- 部署根目录：`/opt/light_hunter/loa_agent_lite`

用户于 2026-08-22 确认：资源公网 IP `101.47.17.169` 和私网 IP `172.31.47.34` 属于同一测试节点。2026-08-28 共享访问拓扑迁移为经统一安全堡垒机访问私网目标；原操作者的 alias 不属于共享事实。当前使用者应按 [access-channel.md](../access-channel.md) 绑定逻辑目标 `agent-lite-test`。

当前部署入口是向 `test` push 后触发 `Deploy on merge`；受保护分支 PR merge 会产生该 push。2026-08-22 的 `Release -> Deploy Pre-release` 关系只保留为历史 run 证据。

### 生产环境

仓库、云资源资料和 2026-08-28 共享拓扑确认：

- GitHub environment：`lc-oc-prod`
- 统一安全堡垒机：公网 `207.166.168.129:22222`；生产节点不对公网暴露 SSH。
- `prod-a`：私网 `10.0.1.218:22`，经安全堡垒机或 BytePlus 受控会话访问。
- `prod-b`：私网 `10.0.1.219:22`，经安全堡垒机或 BytePlus 受控会话访问。
- `prod-a`：`loa-agent-worker` + `loa-agent-gateway`
- `prod-b`：`loa-agent-gateway`
- 用户确认生产 `prod-a` / `prod-b` 前方配置了统一的 BytePlus ALB：实例名 `prod-public-alb`，私网 IP `10.0.0.76`，公网 IP `101.47.23.252`，对外监听 `HTTPS:443`，后端端口 `18765`。ALB 配置没有明确标注后端协议；仓库和运行时只证明该端口上的 Agent Lite Gateway 提供 HTTP 服务，不能替代 ALB 配置证据。
- 用户在 BytePlus ALB 的后端服务器组页签确认：当前健康检查为“未配置”。此前看到的 `/actuator/health` 不属于该后端服务器组的生效健康检查，不用于判断 A/B 健康。当前 ALB 不会依据 Agent Lite 的 `/health` / `/healthz` 自动识别并摘除应用不健康节点；故障时需要依赖其他监控或人工处置。
- 后端权重为 `prod-a=100`、`prod-b=100`，调度算法为加权轮询 `WRR`，会话保持未开启。配置层面为等权轮询，但长连接和连接复用仍可能使实际请求分布不完全均分；同一用户的连续请求可能落到不同 Gateway，正确性依赖 PostgreSQL lease 和 Redis session lock，而不是 ALB 粘性。
- 两台 Gateway 默认均检查 `127.0.0.1:18765/health`
- 只有 bastion 具有公网入口；两个生产应用节点没有公网 IP，必须经 bastion 访问。
- 2026-08-28 曾由一位获批操作员核验新堡垒机和 A/B 的 ED25519 主机指纹，并完成非交互登录测试；其他使用者仍需独立绑定并核验自己的通道。

知识库只记录逻辑目标、云资源、地址、端口和跳板关系，不记录 SSH alias、用户、`IdentityFile` 或私钥内容。当前请求明确要求生产诊断时，按 [access-channel.md](../access-channel.md) 绑定 `agent-lite-prod-a|agent-lite-prod-b`；通道存在不授权状态变更、凭据读取、交互式无边界排查或绕过 host key/跳板机。

当前 `Deploy on merge` 在向 `main` push 后执行生产 check、test、Leo runtime smoke、制品构建，并先部署 `prod-a`、再部署 `prod-b`；受保护分支 PR merge 是正常来源。准确触发条件、目标 SHA 和 GitHub Environment 必须在每次操作前从当前 workflow 重新核验。

## 9. 服务器部署脚本与失败语义

`scripts/deploy-release-on-server.sh` 的主要流程：

1. 获取 `/var/lock/loa-agent-lite-deploy.lock`，阻止同主机并发部署。
2. 核验部署目录、checksum 和至少一个已安装的目标 systemd service。
3. 对每个 Gateway 请求 drain，最多等待 60 秒。
4. 将当前 release 备份到 `.deploy-backups/<timestamp>-before-auto-prerelease`，并单独快照部署前 `.env`。
5. rsync 新 release，排除服务器 `.env`、`.git`、`node_modules` 和备份目录。
6. 在服务器执行 `bun install --frozen-lockfile`。
7. 校验经 stdin 收到的固定运行时配置，以 `0600` 权限原子更新 `.env`，并删除已废弃的旧 provider/translation 配置键。
8. 重启当前主机上实际存在的目标服务。
9. 最多约 60 秒等待每个 Gateway `/health`，随后对每个 Gateway 执行真实 `/api/translate` smoke。
10. 成功后默认只保留最新 1 份备份。

重要边界：

- drain 请求失败、Gateway 不存在或 60 秒超时都会继续部署；这不是硬停止条件。
- drain 只跟踪正在执行的 Agent chat turn，不覆盖 Worker 长任务、Fan Radar API 写入或所有 IM outbox 投递。
- 缺失的 systemd service 会被跳过；只要至少一个目标 service 存在，脚本仍可继续。因此 `prod-a` 缺失 Worker 时，Gateway 仍可能通过 health 并让 workflow 绿色。
- `bun install` 在服务器部署窗口内执行，依赖 registry/网络可用性。
- 新部署失败后 trap 会尝试恢复本机 release 与 `.env` 快照、重新安装依赖、重启并复查 Gateway health，但不会重跑翻译 smoke，也不会核验 Worker。Rollback 本身失败会被吞掉，workflow 仍只报告原始部署失败。
- `prod-a` 与 `prod-b` 串行但不是一个跨主机事务。若 A 成功、B 失败，workflow 不会自动把 A 恢复到旧版，可能形成混合版本。
- 备份是代码目录快照，不是不可变制品注册表；`.env` 不在 release 快照中，而是单独保存并在单机 rollback 时恢复。
- 仓库没有核心 `loa-agent-worker` / `loa-agent-gateway` systemd unit，无法静态确认启动命令、EnvironmentFile、Restart、TimeoutStopSec、stdout/stderr 去向和资源限制。

## 10. GitHub Actions 历史实证（2026-08-20 至 2026-08-22）

### 当时的 main / prerelease

`Release` run `32453476140`，attempt 1：

- event：`push`
- head SHA：`d2fcbf50ea970d6e778a6b8cdab4ec8997f95b81`
- conclusion：success
- Install、Check、Test、Smoke Leo runtime、Build release artifacts、Publish pre-release 全部成功。

随后 `Deploy Pre-release` run `32453543993`，attempt 1：

- event：`workflow_run`
- head SHA：同一 `d2fcbf5...`
- Download、checksum、SSH、upload、server deploy 和 cleanup 全部成功。

这证明 2026-08-22 当时 `main` 对应的 CI、prerelease 制品和测试环境部署 workflow 已成功。随后同日运行时摘要又确认测试服务器内容匹配该 SHA，但 systemd 进程和版本一致仍不证明 Worker、数据库、MQ、模型或 Fan Radar 数据路径健康。

### 最近一次已查到的生产部署

`Deploy Production` run `32329698424`，attempt 1：

- event：`workflow_dispatch`
- head branch：`prod`
- head SHA：`c2a9971bd9633acbb4db06b3bf6829361ffe1726`
- conclusion：success
- Build job 的 Validate ref、Check、Test、Smoke 和制品构建成功。
- Deploy job 的 SSH 配置和两台生产主机部署步骤成功。

该 run 证明 2026-08-20 当时从 `prod@c2a9971...` 完成了 workflow 覆盖的生产部署。2026-08-22 的运行时摘要进一步确认生产 A/B 当前内容均匹配 `prod@47405c8...`，因此服务器已不再是该历史 run 的 `c2a9971...`。但近期 run 列表中未看到 `47405c8...` 的生产部署，且服务器目录存在大量 macOS 元数据文件；当前只能确认实际内容，不能确认它通过 GitHub Actions 还是其他路径部署。

## 11. 发布与回滚操作边界

- 向 `test` push 会部署共享测试环境，向 `main` push 会部署生产环境；受保护分支 PR merge 是正常晋级路径。两者都会改变远端状态，执行前必须确认影响并核验当前 workflow。
- 分支已更新、workflow 已触发和服务器已部署是不同证据层级；不能用前一层替代后一层。
- 生产发布前必须锁定 `origin/main` 完整 SHA、目标 run、两台主机、预期服务和当前已知良好版本。
- 生产 A/B 串行部署，需要明确 B 失败后的 A 主机恢复决策；不能把单机脚本 rollback 当作跨主机自动回滚。
- 版本回滚前必须证明当前 workflow 能绑定准确的已知良好 SHA；不能仅依据历史 run 页面、旧 `prod` 分支名或浮动分支推断 rerun 会部署原始代码。无法证明时停止并报告控制面缺口。
- 单机脚本自动 rollback 只在该主机部署命令失败后尝试；必须再人工核验实际文件、依赖、systemd、Gateway health、Worker 和数据路径。
- 任何生产 deploy、restart、rollback、数据库修正、RabbitMQ 干预、报告重生成或用户数据清理都需单独明确授权。

## 12. 故障定位主路径

### Gateway health 正常但用户请求失败

先按具体入口分流，不把 `/health` 当依赖证明：

1. 核验两台 Gateway 实际 SHA/PID/启动时间和反向代理流量。
2. HTTP IM：检查 PostgreSQL inbox/outbox、lease、Redis session lock、LOA Profile API、模型、message-service 和 dead-letter 状态。
3. Fan Radar API：检查 token 校验、Profile/UTC fallback、ODS 报告表、Runtime Skip/Copy 表、头像签名 API，以及范围严格的 Fan Radar request log。
4. Dashboard/翻译：检查内部网络、静态 dashboard 产物、Runtime PostgreSQL 和翻译 provider。

### Worker 未生成 Live Recap / Fan Radar

依次检查：

1. `loa-agent-worker` 只应在目标 Worker 节点运行，实际版本和启动错误是什么。
2. Profile 用户是否存在、未删除并有正确时区、语言、GUID/TikTok identity。
3. `LIVE_RECAP_DATABASE_URL` / schema 是否指向正确 ODS，账号权限是否满足。
4. 对应本地自然日是否存在 room、`SYSTEM_LIVE_ENDED` 和正确事件窗口。
5. Fan Radar feature flag、scheduler/materializer error、provider payment circuit 和模型错误。
6. `fan_radar_reports` 是否写入、`generated_at` 是否覆盖故障直播、客户端是否读取了预期日期。

只使用 GUID、room ID、日期、计数和时间范围严格的聚合证据；不要返回原始直播事件或报告 payload。

### 用户生命周期积压或删除不完整

检查 queue consumer、retry queues、retry attempt header、Runtime tombstone、各表删除结果、Mem0 settle/erase 和下游对象删除。默认无限重试可能造成长期积压；malformed 消息没有仓库声明的 DLQ，恢复前先核验 broker policy。

### 模型异常

区分：

- provider health inference/models probe；
- Agent run audit 中的真实用户请求失败；
- model fallback/circuit；
- 独立 Bedrock path monitor 的 DNS/TCP/TLS/HTTP 证据。

单一探针绿色不能证明真实 Agent 请求成功；真实请求失败也不自动等于网络故障。

### 部署失败

先确定失败发生在哪台主机、哪个阶段。等待 workflow 结束后分别核验：

- A/B 当前实际版本；
- 单机 backup/rollback 是否执行且恢复后是否健康；
- Worker 是否存在并正常启动；
- 是否形成混合版本；
- drain 超时期间是否有中断任务；
- 服务恢复与已产生数据后果是否为两个独立问题。

## 13. 当前待确认的运维信息

仓库、GitHub Actions 和 2026-08-22 运行时快照仍未回答：

1. BytePlus 控制台实例名和各节点负责人。
2. `prod@47405c8...` 由用户同事部署；实际部署入口以及为何生产 A/B 出现 405 个 macOS 元数据文件，需要向实际部署人核验。
3. 当前正式 Runtime PostgreSQL、ODS PostgreSQL、Redis、RabbitMQ、TOS、LOA API、message-service、Mem0 和模型 provider 的资源名称与只读核验入口。
4. 正式环境 `LOA_DB_TABLE_PREFIX`、`LIVE_RECAP_SCHEMA`、Fan Radar flag、Worker 唯一性等关键配置是否与静态约定一致；只核验键的存在和脱敏状态，不记录值。
5. 测试环境由用户同事部署；Bun 为 `1.3.14`、仓库和 workflow 固定 `1.3.13` 的漂移意图需向实际部署人核验。
6. Agent/Provider Feishu 告警是否在线、目标群负责人，以及至少一次触发—送达—恢复闭环。
7. journald 的目标保留策略；测试/生产 TLS 的 IAM 最小权限、AK/SK 轮换与撤销、敏感样本审查、轮转边界和重启后连续性仍待核验。A/B 基础 Gateway 日志采集已通过 Fan Radar 请求日志确认；若要覆盖所有路由或精确观察请求流量，仍需另行设计统一 Gateway access log 或 ALB 日志。
8. 已确认生产 A/B 前方是 `prod-public-alb`（私网 `10.0.0.76`，公网 `101.47.23.252`），对外监听 `HTTPS:443`、后端端口 `18765`，A/B 权重均为 `100`，调度算法为加权轮询 `WRR`，未开启会话保持；ALB 后端协议未明确标注，后端服务器组未配置健康检查。仍需确认域名/路由、故障节点人工摘除流程、BytePlus 安全组/主机防火墙、混合版本兼容要求和单主机失败后的操作员恢复规则。
9. 历史故障样本、生产回滚实操、Worker 中断恢复和自然直播端到端验收记录。

在这些信息补齐前，可以基于静态代码和 GitHub run 做发布评估与诊断规划，但不得声称已掌握当前生产运行状态。
