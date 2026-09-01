# Crawler 接管知识底稿

更新日期：2026-08-21

本文只整理 `loa-glabal-crawler` 当前可确认的职责、运行链路、数据契约和接管缺口。它不是改造方案，也不代表已经完成线上验收。

## 1. 资料与可信度

当前结论按以下顺序取证：

1. `loa-glabal-crawler` 的 `origin/prod` 静态代码和部署工作流。
2. [LOA Global Crawler 外部交接文档](external-handover.md)。
3. [直播结束 MQ 对接说明](live-end-mq-contract.md)。
4. EulerStream 官方 API 文档。

2026-08-21 刷新后的代码基线为 `origin/prod@f503869ce90b5f389ced6297f052e159787dbea4`。该提交包含已经合入生产分支的飞书告警能力及其 Spring wiring 修复；用户同时确认告警能力已经上线。这里仍需区分两类证据：SHA 证明当前远端生产分支的代码，用户确认说明能力已上线，但两者都不能替代在服务器侧独立核验实际运行 JAR 的 commit/校验值。

外部交接文档声明的 `1807b9411e398ca3ba2221e4e7a45b03005c0279` 现为历史生产提交，不再是最新 `origin/prod`。

外部交接文档中的健康状态、主播数量、连接数量、GitHub Action 结果和本地脏工作区描述，都是带时间的历史快照：

- `UP`、188 个任务、6 个长连接等数字不能作为当前线上状态复用。
- 文档所述旧本地主工作区脏状态已经不适用；2026-08-21 当时核验的本地 clone 是干净且与 `origin/prod` 一致的 `prod`。

## 2. 服务边界

面向粉丝雷达的数据主链路是：

```text
监控目标来源
  -> Redis 共享任务池、due queue、lease
  -> EulerStream 直播状态检查
  -> TikTok LIVE 长连接与事件
  -> TOS part/manifest 归档
  -> live.ended MQ
  -> Data Gateway
```

应区分三类依赖：

- 数据上游：EulerStream/TikTok LIVE，提供直播状态和实时事件。
- 数据下游：TOS 归档和 RabbitMQ 事件通知。
- 控制面依赖：MySQL 目标读取、Redis 任务注册与集群协作。它们不是业务数据下游，但故障会造成“服务存活却没有采集任务”。

Crawler 不应主动写 MySQL 业务数据；生产代码把 MySQL 用于读取监控目标和身份信息。

## 3. 监控目标如何进入 Crawler

生产分支存在四类目标入口：

1. 数据库增量同步：默认约每 30 秒读取一批新目标，单批默认 500。
2. 数据库分页刷新：默认约每 5 分钟复核一批已有目标，单批默认 500。
3. 公开 API：`POST /api/monitoring/public/tasks/start`，可提交一个或多个 TikTok ID，单次最多 100 个去重目标。
4. 手工长期任务和 battle 排期任务：属于同服务能力，需要一并纳入 Crawler 接管范围。

目标会写入 Redis 共享 registry。节点通过 due queue 认领任务，并用 lease 保证同一主播在同一时刻主要由一个节点负责；节点失效后可由其他节点重新认领。

身份处理需要始终区分：

- TikTok username/handle；
- TikTok numeric ID；
- LOA 用户 GUID；
- 目标来源是数据库、公开 API、手工任务还是 battle 排期。

数据库身份优先于纯 API 身份。数据库 LOA 用户归档时使用真实 GUID 和 `is_loa_user=true`；无法匹配数据库的 API 目标使用 TikTok ID 和 `is_loa_user=false`。

## 4. EulerStream 与直播连接

当前生产模式为 `scheduled_live_status_check`，不依赖 Euler Alert callback。

直播状态主检查：

```text
GET https://tiktok.enterprise.eulerstream.com/webcast/anchors/{unique_id}/room_id
```

生产代码中的主要处理规则：

- 400、404、410：视为明确离线。
- 401、403、429：视为 `UNKNOWN`，进入进程级退避，不删除任务，也不直接判定直播结束。
- Euler 5xx 或网络异常：允许一次 TikTok 直连状态兜底。
- 默认每个进程最多 100 个 Euler 状态请求/分钟。
- 遇到限流或鉴权拒绝后至少退避 90 秒，并尊重更长的 `Retry-After`。

只有确认主播正在直播时才建立正式 TikTok LIVE 长连接。普通 WebSocket `onDisconnected` 只会清理连接并安排后续状态检查，不等同于明确下播，也不会立即发送直播结束 MQ。

## 5. 事件处理与 TOS 归档

SDK 的通用 `onEvent` listener 先负责事件归档，精确类型 listener 再负责 MQ、battle 状态和 Gift Chat 等业务副作用。这样每个 SDK 事件只从统一入口归档一次。

TOS bucket：

- PROD：`loa-crawler`
- TEST/UAT：`loa-crawler-test`

对象路径：

```text
yyyy-MM-dd/<identity>/live-<roomId>-<yyyyMMdd-HHmmss>-<sessionShortId>/manifest.json
yyyy-MM-dd/<identity>/live-<roomId>-<yyyyMMdd-HHmmss>-<sessionShortId>/part-00001.json
```

`identity` 对 LOA 用户是 LOA GUID，对非 LOA API 目标是 TikTok ID。

归档时序：

1. 会话创建后写初始 `manifest.json`。
2. part 达到约 4.5 MB、2,000 个事件或约 60 秒 flush 条件时上传。
3. 每个 part 上传成功后更新 manifest。
4. 明确收到直播结束事件后，先把结束事件归档并写最终 manifest，再进入精确 `onLiveEnded` listener 发布 MQ。

强约束：

- MQ 中的归档路径必须取自 TOS 归档服务确认过的 session snapshot，不能在 MQ 层猜测或重新生成 session。
- 没有确认的归档路径时，必须跳过 Legacy `live.ended`，不能发送不存在的 manifest 地址。
- 服务重启后应恢复同一 roomId 的既有目录和 part 序号，避免同一场直播产生两个目录。
- `raw_event_data` 应保持结构化 JSON；重复 key 的兼容处理只发生在该字段内部。

## 6. 直播结束 MQ 契约

两类消息都使用 topic exchange：

```text
openclaw_skill_topic_exchange
```

明确收到 SDK `onLiveEnded` 后，代码按顺序尝试发布：

1. Legacy `live.ended`
   - routing key：`user.pk.invitation.response.<loaUserGuid>`
   - 包含 `archiveDirectory` 和 `manifestPath`
   - 是 Data Gateway 获取 TOS 归档位置的关键通知
2. Monitor `live.ended`
   - routing key：`crawler.event.monitor.<loaUserGuid>`
   - 使用统一实时监控事件格式

共同关联字段包括 `roomId`、`sessionId`、`liveStartedAt` 和 `liveEndedAt`。每条消息独立生成 `eventId`；两类消息应使用 `sessionId` 关联，不能用 `eventId` 互相去重。

`manifestPath` 只是 TOS object key，不包含 bucket 名或 `tos://` 前缀。PROD 完整位置为：

```text
tos://loa-crawler/<manifestPath>
```

当前实现的运维注意事项：

- “发送两条”是正常路径，不是原子事务。
- Legacy 消息缺少已确认的归档路径时会被跳过，Monitor 消息仍可能发布。
- 如果 Legacy 发布直接抛出异常，同一次方法调用中后续 Monitor 发布不会继续执行。
- Publisher 使用 UTF-8 JSON body，没有设置自定义 AMQP properties；当前代码中未看到 publisher confirm、持久化 delivery mode 或应用级重试。
- 因此 Action 成功、服务健康或日志出现 `live.ended` 都不能单独证明两条消息已被正确路由和消费。

实时 monitor 还可能发布 `live.started`、`comment.created`、`like.created` 及已映射的其他互动事件。它们与包含归档路径的 Legacy `live.ended` 用途不同。

## 7. 其他项目能力

`origin/prod` 还包含：

- battle/PK 排期、`ONGOING`/`DONE` 状态处理；
- 公开主播监控 API；
- Euler OAuth；
- 高价值礼物触发的 LLM 感谢语和 Euler Webcast Chat。

这些能力虽然与粉丝雷达核心数据流的直接关系不同，但都属于 Crawler 工程的完整接管范围。后续知识、操作文档和 Skill 需要覆盖它们的用途、入口、配置、依赖、发布验证和故障定位，不能只登记其存在。

## 8. 发布与验收基线

代码分支与部署 profile：

- PR 合入 `test` -> `SPRING_PROFILES_ACTIVE=test`
- PR 合入 `uat` -> `SPRING_PROFILES_ACTIVE=uat`
- PR 合入 `prod` -> `SPRING_PROFILES_ACTIVE=prod`
- 直接 push `test` 也会触发部署
- `workflow_dispatch` 可选择 test/uat/prod

GitHub Actions 使用 Java 17，依次执行 Maven 测试、打包、同步 JAR、重启 `loa-global-crawler.service`，最后请求 `/actuator/health`。

### 实际环境拓扑

当前只有一个可用环境，即 Crawler 生产环境：

- 权威部署分支：`prod`
- BytePlus 云服务器名：`LOA-crawler-prod`
- 公网 IP：`101.47.11.6`
- 私网 IP：`10.0.1.204`
- systemd 服务：`loa-global-crawler.service`
- 工作目录：`/opt/loa-global-crawler`
- 应用端口：生产 profile 未覆盖默认值，当前代码使用 `8080`

常规生产发布是在 PR 合并到 `prod` 后自动触发 GitHub Actions；用户已经人工确认和验证这条 merge 发布路径。`workflow_dispatch` 仍是已经实证可用的同 SHA 重部署和特殊授权操作入口。两者都只在对应 Action 覆盖范围内证明构建、传输、重启和 health，不自动证明完整数据面成功。

“只有一个可用生产环境”是环境事实，不应扩张成“服务器上已经核验只有一个 JVM 进程”；实际 PID、启动时间和运行 JAR 仍需要服务器侧证据。

### Workflow 历史核验

2026-08-19 对 `.github/workflows/deploy.yml` 的全部 Git 修改记录做了只读核验，并在核验前重新执行了 `git fetch origin --prune`：

- 2026-06-01，`9fc3a62` 首次创建部署 workflow 时已同时包含 TEST、UAT、PROD；TEST 支持 PR 合并、直接 push 和手工 `workflow_dispatch`。
- 2026-06-01，`6af0a43` 只把部署产物传输从 rsync 调整为 scp。
- 2026-06-02，`9263e5f` 增加 PROD 默认部署目标、分环境 SSH Secret 和 systemd unit 安装，没有删除 TEST。
- 2026-06-14，`cd34a92` 把 JAR 上传调整为 `.next` 后原子替换，没有删除 TEST。
- 2026-06-14，合并提交 `d963f94` 汇合上述生产部署配置和原子替换逻辑；TEST 触发器与配置仍被保留。
- 此后直至 `origin/prod@1807b941`，部署触发器没有变化。
- 2026-08-21，告警能力合入后，workflow 新增飞书凭据校验、安全落盘和 systemd `EnvironmentFile` 注入；TEST/UAT 触发器仍未被删除。

当前 `origin/prod@f503869` 仍明确保留：

- PR 合入 `test` 触发部署；
- push `test` 触发部署；
- `workflow_dispatch` 的 `test` 选项；
- `TEST_DEPLOY_HOST`、`TEST_DEPLOY_USER`、`TEST_DEPLOY_PORT`、`TEST_DEPLOY_ROOT`；
- `TEST_DEPLOY_SSH_KEY` 和 `TEST_DEPLOY_KNOWN_HOSTS`。

因此从 Git 历史只能得出：**TEST 没有在代码或 workflow 配置层面被下掉。** `test` 分支最后停留在 2026-06-03 的 `0b44233`，后续 PR 主要合入 PROD，说明 TEST 后续没有继续跟随发布；它不能证明测试服务器存在或可用。

后续人工确认结果：Crawler 当前不存在可用的测试环境，实际部署能力只能在生产环境验证。因此 TEST/UAT 相关分支、触发器、默认主机和配置只能视为历史残留，不得据此发起非生产部署。后续发布 Runbook 和 Skill 必须采用生产专用的风险控制、回滚和证据留存流程。

仅 health 为 `UP` 不足以验收。发布后至少还需要验证：

1. `/api/monitoring/status` 中数据库/API 目标存在，调度时间持续推进。
2. Euler 没有持续 401/403/429，5xx 没有造成请求放大。
3. 真实直播能建立长连接。
4. TOS 在直播过程中持续生成 part，最终 manifest 完整。
5. Legacy MQ 的 `manifestPath` 与 TOS 实际 object key 字符级一致。
6. Data Gateway 确实收到并处理对应结束消息。
7. 同一 roomId 没有因重启或断线产生重复目录。

外部交接文档指出 TEST/UAT 分支落后 PROD，且 TEST 默认部署目标存在历史配置风险。执行任何非 PROD 发布前都需要重新核验目标分支、实际服务器和环境变量，不能直接把旧 TEST/UAT 反向合并进 PROD。

## 9. 日志与已上线告警能力

### 9.1 安全日志入口

生产日志允许受控只读访问：当前请求明确要求生产诊断时，按 [生产访问通道与可移植绑定](../access-channel.md) 将 `crawler-prod` 绑定到当前使用者已获批的访问通道，再查询 `LOA-crawler-prod` 的服务状态、版本和限定时间窗日志。不得索取、保存或代持密钥，不得读取 profile、`.env` 或完整业务 payload，不得绕过 host key/网络边界，也不得执行服务、文件、配置或数据状态变更。

当前代码可确认的主要入口：

- 应用 stdout/stderr：`/opt/loa-global-crawler/runtime/manual-monitoring.log`
- systemd 单元：`loa-global-crawler.service`
- systemd 辅助日志入口：`journalctl -u loa-global-crawler.service`

应用主体日志由 `runtime/start-manual-monitoring.sh` 追加到 `manual-monitoring.log`；`journalctl` 更适合检查 systemd 启停、重启循环和启动脚本异常。实际查看时由人执行命令，只向 AI 回传完成脱敏且与故障时间窗相关的片段。

### 9.2 BytePlus TLS 集中日志

2026-08-24，用户授权在 Crawler 生产主机安装 BytePlus LogCollector，并在操作完成后确认日志已经进入 TLS。以下为当时取得的运行时证据，只表示该时间点状态，后续故障诊断仍应重新核验：

- 实际主机名为 `ECS-Prod-Crawler`；BytePlus 资源显示名为 `LOA-crawler-prod`。
- 已安装 LogCollector `2.4.2`，systemd 服务名为 `logcollectord.service`；核验时为 `active`、`enabled` 且 `NRestarts=0`。
- TLS Region 为 `ap-southeast-1`，采集端点为 `https://tls-ap-southeast-1.ibytepluses.com`。该版本端点缺少 `https://` 时会持续出现 `unsupported protocol scheme ""`。
- 采集规则名为 `loa-global-crawler-prod-manual-monitoring`，输入文件为 `/opt/loa-global-crawler/runtime/manual-monitoring.log`，类型为 multiline，启用 `TailFiles`，初始尾部大小为 `10 KiB`。
- 固定字段为 `component=crawler`、`environment=prod`、`service=loa-global-crawler`，并启用主机名字段。
- LogCollector 入口目录为 `/usr/local/logcollector`，运行日志位于 `/usr/local/logcollector/logs/`。配置文件包含敏感认证信息，禁止输出完整内容；当次核验时实际配置文件权限为 `600 root:root`。
- 当次指标为 `HeartbeatStatus=normal`、`HarvesterNum=1`、`RuleNum=1`；成功请求和成功日志计数均大于零，发送失败和丢弃均为零。Crawler 同时为 `active`，Actuator health 返回 `UP`。
- 首次从文件尾部采集出现过一次 multiline 起点告警；后续抽样中非空行没有持续不匹配 begin regex，因此未将其判断为持续解析故障。

验证时必须依次区分：应用日志是否继续增长、采集器是否运行、采集器是否成功发送，以及指定 TLS Topic/索引是否可检索。LogCollector heartbeat 不是 Crawler 应用 heartbeat，TLS 有日志也不证明 TOS、MQ、Gateway 或 PostgreSQL 数据路径成功。具体只读命令、TLS 查询顺序和脱敏边界维护在 [`crawler-diagnosis.md`](../crawler-diagnosis.md)。

当前仍未完成应用日志滚动/本地保留策略、TLS 保留与索引治理、采集链路独立告警，以及 Codex 受控只读查询 TLS 的接入。

### 9.3 告警投递机制

2026-08-21 用户确认 Crawler 告警能力已经上线；以下实现事实来自 `origin/prod@f503869`：

- 当前唯一渠道是带 HMAC-SHA256 签名的飞书自定义机器人文本消息；没有邮件、短信、BytePlus Cloud Monitor 或第二告警通道兜底。
- 配置键为 `FEISHU_ALERT_WEBHOOK_URL` 和 `FEISHU_ALERT_SIGN_SECRET`；知识库只记录键名，不记录值。
- 生产 workflow 要求两个 Secret 同时存在且为单行值，否则在测试、打包和部署前失败。部署时将其安装到 `/etc/loa-global-crawler/feishu-alerting.env`，文件属主为 `root`、权限为 `0600`，再由 systemd `EnvironmentFile` 注入。
- 普通运行期告警通过单进程、单 worker 的异步内存队列发送；队列容量为 64，提交使用非阻塞 `offer`，不会让告警网络请求阻塞采集主流程。
- 相同告警 key 在本进程内抑制 5 分钟。抑制时间从“进入队列”开始计算，因此即使实际发送失败，该 key 仍会被抑制；进程重启会清空抑制状态，多实例之间也不共享抑制记录。
- 单次飞书请求的连接/请求超时为 5 秒，没有应用级重试。HTTP、响应 JSON 或飞书返回码异常只写本地 error 日志，不回抛到业务调用方。
- 队列已满时新告警被丢弃并写本地 warning；关闭进程时最多等待 6 秒排空，超时后剩余告警丢弃。
- Spring 启动失败是例外：`StartupFailureReporter` 在 Spring 上下文尚未建立时同步直发，绕过异步队列和 5 分钟抑制，发送失败不会替换原始启动异常。若 systemd 持续自动重启，可能重复发送同类启动失败告警。
- 告警文本包含实例 node ID、首个 active profile、级别、类型、UTC 时间和各诊断字段；单条文本最多 18,000 个 Unicode code point，错误摘要最多 800 个 code point。
- 告警 key 只参与内部去重，不显示在飞书正文中；正文“时间”是 worker 实际发送时间，不是故障首次发生时间。现场需要用标题和诊断字段映射到本文列出的内部 key。
- 错误摘要会遮蔽常见数据库/RabbitMQ URL、URI user-info、Authorization/Cookie、Bearer token 和常见 secret 赋值，并精确遮蔽当前飞书凭据。它不是任意敏感内容的完备 DLP；诊断时仍不得把原始凭据或完整业务 payload 放入告警字段。

### 9.4 当前触发覆盖

ERROR 告警：

- `service-startup-failed`：Spring 启动失败；字段包括 environment、error type、error。
- `schedule-poll-failed`：启用的 Battle 排期源请求或解析失败；本轮轮询终止，等待下次调度。当前生产 profile 的仓库默认值关闭该排期源，因此只有被运行时覆盖为启用时才会触发。
- `status-worker:<streamer>`：直播状态检查 worker 非预期退出；字段包含 streamer、worker、error type，随后尝试恢复重试节奏。正常 shutdown/cancellation 不告警。
- `cluster-coordination-unavailable`：Redis due target 领取、lease 获取或续租抛异常；字段中的 operation 用于区分 `claim_due_targets`、`acquire_lease`、`renew_lease`。
- `archive-event:<session-or-streamer>:<event-type>`：普通直播事件的归档写入失败；字段包含 streamer、room、session、event type、archive prefix 和 error。
- `archive-finalize:<session-or-streamer>`：直播结束归档或最终 manifest 写入失败；保留 session 供后续 flush 重试。
- `mq-publish:outside-battle`：Battle 状态 MQ 配置不完整或实际发布失败。
- `mq-publish:monitor:<event-type>`：Monitor 事件缺少 routing identity、MQ 配置不完整或实际发布失败。
- `mq-publish:legacy-live-ended`：Legacy `live.ended` 缺少 LOA GUID/已确认归档路径、MQ 配置不完整或实际发布失败。

WARNING 告警：

- `target-sync:incremental` / `target-sync:refresh`：数据库目标增量同步或分页刷新失败；当前轮降级，等待下次调度。
- `identity-lookup:redis` / `identity-lookup:database`：公开 API 目标的身份解析失败；Redis 失败后尝试数据库，数据库也失败时按外部目标继续，因此需要关注可能的身份/归档路径降级。
- `cluster-coordination-degraded`：Redis target state、next probe 或 GUID index 等非核心协调操作失败；具体操作记录在 operation 字段。

MQ 告警需要结合控制流判读：发布器内部的配置/网络失败会先告警再抛异常；而 Monitor/Legacy 的 LOA GUID 或归档路径前置条件缺失会告警后直接跳过该条消息。RabbitMQ 整体禁用时，发布是无告警的 no-op。

### 9.5 已知观测边界

- 这套能力以异常边界告警为主；LogCollector heartbeat 只覆盖采集器到 TLS，不是 Crawler 应用 heartbeat。当前仍不提供独立的应用心跳、吞吐/延迟 SLO、无事件检测、队列积压、恢复通知或端到端业务成功告警。
- Euler 401/403/429/5xx、普通直播断线和持续 `UNKNOWN` 目前主要依赖日志与状态信息，不会由上述告警逐项通知。
- `prepareSession` 失败、周期性 open-session flush 失败、shutdown flush 失败，以及 pre-session 缓冲达到上限后丢弃最老事件，都存在只写本地日志的路径。为保留事件并允许重试而产生的 `RetainedArchiveEventException` 也会刻意避免重复告警；直播结束 finalization 失败才进入 `archive-finalize`。
- RabbitMQ 当前只对同步 `basicPublish` 异常告警；没有 publisher confirm、mandatory return 或下游业务 ACK，因此 broker 接受后未路由、路由后未消费等情况不能由 Crawler 发布告警证明。
- 通用 key（如 `cluster-coordination-unavailable`）会让不同 operation/streamer 在同一进程的 5 分钟窗口内互相抑制；告警群中看到的一条不代表窗口内只有一个对象失败。
- 告警发送通道自身失败只能从应用日志发现；它无法通过同一个飞书通道可靠地自报告。
- 告警正文没有 commit SHA、构建版本、GitHub run/deployment ID、主机 IP 或 trace ID；字段中的 streamer、LOA GUID、room/session/event/battle ID 和 archive prefix 具有可识别性，只应在获批告警群和脱敏诊断上下文中处理。
- Gift Chat、BytePlus LLM、Euler OAuth/chat send 等辅助能力目前仍以日志为主，没有进入这套飞书告警覆盖。
- 代码测试覆盖格式、签名、脱敏、超时/飞书返回校验、Spring wiring、队列满、去重、发送失败及主要业务告警边界；这些测试和用户确认的“已上线”都不等于已经取得一次真实故障触发、飞书送达、处置和恢复的闭环证据。

上述边界是后续故障定位/恢复 Skill 的输入：收到告警时可把标题和关联字段映射到内部 key，再收敛日志范围；没有告警时仍不能据此排除 Euler、TOS 周期 flush、断线、积压或告警通道自身故障。

## 10. 故障定位主路径

### 主播未被监控

依次检查目标是否进入 `watchTasks`、目标来源与身份、下一次 probe、Euler 返回、Redis due queue/lease，以及确认 LIVE 后的连接异常。

### 有直播但没有 TOS

依次检查 active connection、archive session 创建日志、part 上传日志、bucket/profile、TOS PUT/list 错误。不能只等到 `live.ended` 才判断是否应该存在归档。

### 收到 MQ 但 manifest 不存在

直接以 MQ `manifestPath` 查询 TOS，核对 confirmed archive snapshot，并按 roomId 搜索是否存在多个目录。不要从 sessionId 或时间重新推导路径。

### TOS 正常但 Data Gateway 未处理

区分 Legacy 和 Monitor routing key，核对 Crawler 发布日志、exchange binding、队列积压/死信、消费者状态和 Data Gateway 幂等记录。不能只根据 Monitor `live.ended` 推断 Legacy 消息也一定成功。

## 11. 生产发布与回滚实证

常规生产发布是 PR 合并到 `prod` 后由 GitHub Actions 自动部署，这条 merge 发布路径已经由用户人工确认和验证。另在 2026-08-19 用户明确开放的生产操作窗口内，完成了一次无代码变更的 `prod` 同 SHA 手工发布和一次发布式回滚；详细 run 证据见 [生产发布与回滚验证记录](release-validation-2026-08-19.md)。

已实证：

- `workflow_dispatch` 从 `prod` ref 选择 `environment=prod` 可以完成 Maven 测试、打包、生产 SSH 同步、systemd 重启和 `/actuator/health` 验证。
- 发布 run `32241855223` 精确 checkout `1807b9411e398ca3ba2221e4e7a45b03005c0279`；72 项测试无失败，job 约 1 分 36 秒，最终 `health=UP`。
- 重新运行发布前最后一次成功生产 run `32033664076` 的 attempt 2，可以再次精确 checkout 同一 `prod` 提交并完成全套部署；72 项测试无失败，job 约 1 分 32 秒，最终 `health=UP`。
- 历史 run 的重新运行会保留原 run ID 并增加 `run_attempt`；验证证据必须同时记录 run ID 和 attempt。

能力边界：

- 这次验证的是**发布式回滚**：从 GitHub Actions 页面重新运行一个经过核验的历史成功 run，重新构建并部署已知良好提交。后续可通过 GitHub Actions 页面或 GitHub API 执行同类操作，但仍须锁定目标 run/commit 并核验实际 checkout SHA。
- 现有 workflow 不备份旧 JAR，也没有 rollback input 或失败后的自动恢复，因此不能把上述结果写成“原 JAR 已恢复”。
- 2026-08-24 曾由一位获批操作员确认安全访问路径可连接 Crawler 生产主机；这是历史拓扑证据，不是另一位使用者的 SSH 配置或持续授权。当前请求将具体生产诊断目标置于范围内时，仍需按共享目标独立绑定当前通道；任何状态变更须针对准确操作另行取得明确授权。
- 2026-08-24 的 LogCollector 安装窗口取得了服务 active、health `UP` 和日志采集指标证据，但不会倒推补齐 2026-08-19 发布实验当时缺失的服务器侧证据，也没有证明当前实际 JAR SHA、JVM 实例数或数据路径状态。
- 操作窗口由用户确认可用，但发布前没有通过 `/api/monitoring/status` 独立证明 `activeConnectionCount=0`。
- 两次 Action 的绿色结果只证明构建、传输、systemd active 和健康端点；没有等待自然直播结束事件，因此尚未完成 TOS、MQ、Gateway 和 PostgreSQL 数据面的发布后验收。
- Action 给出 `actions/checkout@v4`、`actions/setup-java@v4` 的 Node.js 20 兼容警告，并提示 `setup-java v4` 已弃用；这属于 CI 维护项，不影响本次成功结论。

因此 Crawler 发布 Skill 可以使用这条已验证路径，但必须把“进程发布成功”“发布式回滚成功”和“数据链路业务验证成功”定义为三个不同结论。

## 12. 仍需补齐的信息

这些信息是形成可执行 Crawler Skill 和操作手册前的主要缺口：

1. 生产服务器实际运行 JAR 的 commit/校验值、JVM 进程数量、PID、profile 和启动时间；服务器名、网络地址以及 2026-08-24 时间点的 systemd active/health `UP` 已确认，但仍需按诊断时间重新核验。
2. 生产 MySQL、Redis、RabbitMQ、TOS、EulerStream 资源的名称、负责人和凭据获取/轮换入口；文档不保存凭据值。仓库 profile 中出现的敏感字面量不得复制到知识库，后续需要确认轮换和迁移责任人。
3. Data Gateway 线上实际 binding、queue/DLQ 积压、consumer 状态、访问权限及当前运行版本；静态 exchange/routing/重试语义已经记录，不等于线上实证。
4. TOS 生命周期、保留周期、历史错误目录处理方式和权限负责人。
5. EulerStream 组织权限、套餐额度、跨环境是否共享 quota、配额告警负责人。
6. Gift Chat、OAuth、battle 和公开 API 的线上启用状态、依赖资源、验收方式及负责人。
7. 应用日志的实际权限和轮转/本地保留策略、TLS 保留与索引治理、采集链路独立告警、告警群负责人，以及至少一次“真实故障触发 -> 飞书送达 -> TLS 日志定位 -> 恢复确认”的闭环证据。
8. 旧 JAR 制品级恢复、发布前活跃连接检查、发布后的自然直播数据面验收，以及至少一到两个历史故障案例。

这些缺口分别对应长期目标中的“可发布、可维护、出问题可定位”。在缺口补齐前，可以形成事实型知识底稿，但不应把静态代码推断包装成已验证的生产操作 Skill。
