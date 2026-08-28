# 端到端诊断

当 Fan Radar 数据缺失、延迟、重复或不一致，或尚不清楚故障组件时，使用本路径。提出恢复方案前，先定位第一个失效边界。

Agent Lite 代码仓库：[Lighthunter-PTE-ltd/loa_agent_lite](https://github.com/Lighthunter-PTE-ltd/loa_agent_lite)。以下静态事实于 2026-08-21 根据 [`main@263c5466926b01b6c6801e5d1528cd808bc5816a`](https://github.com/Lighthunter-PTE-ltd/loa_agent_lite/tree/263c5466926b01b6c6801e5d1528cd808bc5816a) 完成复核；使用本地 clone 时先核验 origin，采取操作前还应核验更新代码和已部署状态。

## 数据路径

```text
目标来源
  -> Crawler target sync / Redis due scheduling / lease
  -> EulerStream live-status 查询
  -> TikTok LIVE 连接和事件采集
  -> TOS 归档 parts 和 completed manifest
  -> Crawler Legacy live.ended RabbitMQ 消息
  -> 共享 Gateway queue
  -> Gateway main 或 test consumer
  -> TOS manifest/part 校验和解码
  -> PostgreSQL 事件行，再执行 user/avatar enrichment
  -> loa_agent_lite / Fan Radar 读取并展示数据
```

Monitor 和 Legacy `live.ended` 是两类独立消息，各有独立的 event ID。应按 room/session identity 关联，不能假定它们的 event ID 相同。

## 从范围明确的故障键开始

只收集实际存在的信息：

- 症状和预期行为；
- 时间窗口和时区；
- streamer identity 和 LOA GUID；
- room ID 和 session ID；
- 准确的 Legacy MQ event ID；
- 该消息中的准确 `manifestPath`；
- 已知时提供 Gateway instance/run/version；
- 一条有代表性的下游缺失或重复记录。

优先使用 room ID、session ID、准确的 manifest path 和 LOA GUID 作为跨节点关联键。不要根据时间戳杜撰 manifest key，不要根据告警推断消息已投递，也不要按 event ID 关联两类 Crawler 消息。

首次排查至少需要：一个症状、一个已校验的关联键，以及带时区且范围明确的时间窗口。如果用户只提供 room ID，应在搜索生产日志前询问大致的开播/结束时间。逐节点推导 session ID、Legacy event ID、准确的 manifest path 和 host GUID；不得因缺少时间信息而索取全部留存日志。

## 定位第一个不满足的约束

### 1. 目标从未被调度或连接

核验 target source、identity resolution、Redis registry/due state、lease claim 和 renewal、next-probe progression、Euler response/backoff、confirmed live status 和 TikTok LIVE connection。故障边界进入 Crawler 后，读取 [crawler-diagnosis.md](crawler-diagnosis.md)。

### 2. 已存在直播连接，但没有完整归档

核验 archive session 创建、直播期间的 part object、periodic/final flush、final manifest completion、总 part/event metadata，以及同一 room/session 的重复归档目录。没有 Feishu 告警不能排除只记录日志的归档路径发生故障。

### 3. 归档存在，但没有匹配的 Gateway 结果

使用准确的 Legacy `manifestPath`。确认 Crawler 是否尝试发布 Legacy 消息、消息是否路由到 `loa_data_gateway_live_ended`、由哪个竞争消费的 Gateway 实例接收，以及消息是已 ACK、重新入队，还是发送到 `loa_data_gateway_live_ended_dlq`。随后检查 manifest validation、第一个失败的 part，以及已经提交到 PostgreSQL 的 parts。读取 [gateway-diagnosis.md](gateway-diagnosis.md)。

### 4. 事件行存在，但 Fan Radar 数据缺失或错误

核验预期的 production/test event schema、标识符和数量、duplicate/conflict handling、user-info 行、avatar job，以及 `loa_agent_lite` 使用的准确下游 query/filter/cache。到达此边界时，不要假定重新部署 Crawler 或 Gateway 能修复现有数据。

## Agent Lite / Fan Radar 静态关口

以下是本地 `loa_agent_lite` main 分支中的代码/文档事实，不能证明实际部署状态：

- Fan Radar 通过 `LIVE_RECAP_DATABASE_URL` 和 `LIVE_RECAP_SCHEMA` 读取源数据；静态部署资料规定正式环境应配置为 `prod_liveonair_tiktok`。ODS 源表为 `ods_tiktok_live_event_detail`，报告存储在同一 schema 的 `fan_radar_reports` 中。
- 除非 `LIVE_RECAP_FAN_RADAR_ENABLED=true`，否则计划 materialization 处于禁用状态。
- Worker 按 `FAN_RADAR_POLL_INTERVAL_MS` 扫描普通 Profile 用户，并使用各 creator 的 Profile 时区和当前本地自然日。缺少时区的用户会被排除；普通用户通过 host/LOA GUID 与 ODS 匹配。自动扫描会跳过 `isOpsTest=true` 的用户。
- 只有当某 room 的 ODS 事件包含 `SYSTEM_LIVE_ENDED` 时，该 room 才符合条件。单独的 gift/comment/follow 不会触发生成。
- 内存中的 scan checkpoint 基于 host GUID、summary date 和 completed-room count；生成失败不会推进 checkpoint，后续扫描会重试。
- 只有完整校验通过后，才会在 `fan_radar_reports` 中按 `(host_guid, summary_date)` upsert canonical report。判断报告是否覆盖故障直播前，应检查 `generated_at` 和 report window。
- 客户端 API 通过认证信息识别当前用户，而不使用调用方提供的 `hostGuid`；Profile 缺少时区时返回 `403`。
- `GET /agent/v1/me/fan-radar/latest` 会在当天报告存在时返回该报告，否则返回最新历史报告；`404 report_not_found` 表示该已认证用户完全没有报告，不一定表示没有源活动。成功响应但返回较早的 `summary_date`，与 404 是不同症状。
- 客户端只重新读取报告；不会启动生成，也不暴露内部 job 状态。
- 静态部署资料将 Worker 服务命名为 `loa-agent-worker`，将 release 放在 `/opt/light_hunter/loa_agent_lite` 下，并只把 Worker 分配给逻辑生产节点 `prod-a`；Agent Gateway listener 默认为 `127.0.0.1:18765`。这些名称仍需运行时确认。

确认 Gateway 数据存在后，按以下顺序检查：Profile-to-host-GUID mapping 和时区、正确的生产 ODS schema、room 级 `SYSTEM_LIVE_ENDED`、feature flag 和 Worker runtime、materializer error/retry 证据、`(host_guid, summary_date)` 报告是否存在及其 coverage window、已认证 API 结果/返回的 `summary_date`，最后检查客户端渲染。使用只读聚合查询并返回标识符/数量，不要返回原始事件或报告 payload。第一次 ODS 聚合只应包含 GUID、room ID、事件总数、`SYSTEM_LIVE_ENDED` 数量，以及源时间戳的最小值/最大值。

可使用 `systemctl status loa-agent-worker` 和限定时间范围的 `journalctl -u loa-agent-worker` 缩小静态日志范围，并查找 `Fan Radar materializer error`；不得将这些名称当作线上证明。随附知识尚未确认实际生产 host/IP、已部署 SHA、运行时配置值、日志保留策略或安全的数据库访问路径。不要杜撰这些信息。如果诊断到达此边界，应检查更新的交接知识/本地 workflow，或向负责人询问获批的只读入口；所有仍未确认的项目都应报告为运维知识缺口。

## 各节点证据包

证据应保持最小化并完成脱敏：

1. **Crawler：** 运行版本/启动时间、target/probe state、connection/session 证据、archive prefix、part/finalize 结果和 Legacy 发布结果。
2. **TOS：** 准确的 object key、manifest completion flag、room/session/GUID identity、声明的 part 数量和有代表性的 object metadata。不要下载无关的用户数据。
3. **RabbitMQ：** exchange/routing/queue identity、event ID、准确的 manifest path、ready/unacked/DLQ 状态，以及在可观察时确认由哪个 consumer 处理消息。
4. **Gateway：** main/test 版本、processing attempt 和 classification、第一个失败的 part、ACK/NACK 结果、import summary 和 user/avatar 结果。
5. **PostgreSQL/下游：** 两个相关 schema 中范围严格的数量和标识符、user/avatar 状态，再到对应的 Agent Lite/Fan Radar 读取结果。

将每项证据标记为静态、GitHub run、运行时、数据路径或操作员确认。某一份日志中没有记录，不能证明事件从未发生；尤其要考虑两个竞争消费的 Gateway consumer 和日志轮转。

## 恢复边界

诊断不代表授权恢复。定位第一个失效边界后，应说明最小候选操作及其数据后果，再单独取得授权。

- 代码回滚可以恢复进程行为，但不能撤销已 ACK 的消息或已提交的数据行。
- 服务重启可能中断活跃的 Crawler session 或 Gateway worker，并且不能修复历史数据。
- DLQ 重放要求：准确的消息范围、故障原因已消除、幂等性/部分写入评估、consumer/version 选择、观察计划和停止条件。绝不能仅凭聚合症状重放整个 DLQ。
- 手动 Gateway manifest 导入只处理事件导入；它会跳过 user/avatar enrichment，无法修复此类故障。
- 数据库/TOS 更正或下游补偿属于独立变更，必须评审 row/object 范围及回滚计划。

如果混合版本、schema 语义或下游行为导致安全操作不明确，应停在已定位的边界并提出尚未解决的设计决策，不得临时拼凑生产修复方案。

## 故障交接

交接内容：

- 第一个已证明健康的节点，以及第一个失败/未知节点；
- 使用的关联键和时间窗口；
- 已收集证据及其层级；
- 事实与假设；
- 服务可用性与历史数据正确性是否属于两个独立问题；
- 下一项最小只读检查；
- 任何拟议变更、影响、所需授权、验证方式和停止条件。
