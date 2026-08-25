# Crawler 日志接入 BytePlus TLS 与 Codex 诊断架构

- **状态：** IN_PROGRESS
- **最后更新：** 2026-08-24
- **适用组件：** `loa-glabal-crawler`
- **目标环境：** 生产环境
- **文档性质：** 运维架构记忆、实施状态与后续决策基线

## 1. 当前目标

建设两条连续但可独立交付的能力：

1. 将 Crawler 生产应用日志可靠采集到 BytePlus Torch Log Service（TLS），使其可集中检索、分析和告警。
2. 让 Codex 在获得告警上下文后，结合 `loa-data-pipeline-ops` Skill、代码和受控的 TLS 日志查询，返回可复核的问题定位。

理想链路为：

```text
发现告警
  -> 向 Codex 提供结构化告警信息
  -> Codex 根据运维 Skill 确定诊断路径
  -> Codex 通过受控只读工具查询 TLS
  -> Codex 返回问题定位、直接证据、置信度和剩余未知项
```

成功标准不是“模型给出答案”，而是操作员能复核查询条件、时间范围、日志证据和推断边界。

## 2. 当前实施状态

截至 2026-08-24：

- **已完成：** 在 Crawler 生产主机安装 BytePlus LogCollector。
- **已完成：** 建立 `manual-monitoring.log` 的 multiline 采集规则和固定字段。
- **已完成：** 验证采集器 heartbeat、规则、harvester 和成功发送计数。
- **已完成：** 操作员确认日志已经进入 BytePlus TLS 并可在目标日志系统中查看。
- **已完成：** 将环境事实和人工排障步骤写入运维 Skill。
- **未完成：** 应用日志滚动与本地保留策略。
- **未完成：** TLS 保留、索引与费用治理的长期基线。
- **未完成：** LogCollector/TLS 采集链路的独立告警。
- **未完成：** 告警后由人确认并向 Codex 提供结构化上下文的固定流程。
- **未完成：** Codex 对 TLS 的受控只读查询工具。
- **未开始：** Alert Bridge 和事件驱动自动诊断。

当前结论只能表述为“Crawler 文件日志到 BytePlus TLS 的采集与检索链路已接通”。这不证明 Crawler 业务健康，也不证明 TOS、RabbitMQ、Gateway、PostgreSQL 或 Fan Radar 数据路径成功。

## 3. 当前运行证据快照

以下是 2026-08-24 的时间点证据，诊断时必须重新核验：

- BytePlus 资源显示名：`LOA-crawler-prod`。
- 实际主机名：`ECS-Prod-Crawler`。
- 私网 IP：`10.0.1.204`。
- Crawler 服务：`loa-global-crawler.service`。
- 应用日志：`/opt/loa-global-crawler/runtime/manual-monitoring.log`。
- LogCollector 版本：`2.4.2`。
- LogCollector 服务：`logcollectord.service`。
- TLS Region：`ap-southeast-1`。
- 采集端点：`https://tls-ap-southeast-1.ibytepluses.com`。
- 采集规则：`loa-global-crawler-prod-manual-monitoring`。
- 采集类型：multiline，启用 `TailFiles`，初始尾部大小 `10 KiB`。
- 固定字段：`component=crawler`、`environment=prod`、`service=loa-global-crawler`，并启用主机名字段。
- 核验时 `logcollectord.service` 为 `active/enabled` 且 `NRestarts=0`。
- 核验时 `HeartbeatStatus=normal`、`HarvesterNum=1`、`RuleNum=1`；成功发送计数大于零，失败和丢弃为零。
- 同期 Crawler 为 `active`，`/actuator/health` 返回 `UP`。
- LogCollector 配置包含敏感认证信息，禁止输出完整内容；核验时实际配置文件权限为 `600 root:root`。

LogCollector `2.4.2` 的 endpoint 必须包含 `https://`。缺少协议时会出现 `unsupported protocol scheme ""`，heartbeat 和规则获取无法正常完成。

仍未确认或尚未形成长期基线：

- 当前实际运行 JAR SHA、JVM 实例数量和 profile。
- 日志日增量、峰值、单条最大长度和敏感字段分布。
- 应用日志滚动、本地保留天数和磁盘上限。
- TLS Topic 保留期、索引成本和长期容量策略。
- Codex 查询身份能否被严格限制到目标 Topic，以及短期凭据方案。

## 4. 架构决策

### D1：使用 LogCollector 采集主机文件

主链路采用安装在 Crawler ECS 上的 BytePlus LogCollector，直接采集应用日志文件，不在 Crawler JVM 中增加 TLS SDK 或自定义 Logback Appender。

理由：

- 与当前单机、Spring Boot、文件日志形态直接匹配。
- TLS 写入、重试、限流和认证不进入 Crawler 进程。
- 采集器可以独立维护读取进度和规则。
- 当前方案已经通过生产运行证据验证。

### D2：应用负责日志滚动

首版继续采集当前文件；长期应由 Spring Boot/Logback 管理滚动、单文件大小和保留数量。

不把外部 `copytruncate` 作为长期首选，因为复制与截断窗口可能产生丢失或重复；直接 rename 也可能遇到 JVM 继续持有旧文件描述符。

### D3：TLS 是日志事实源

不把全量日志“导入 Codex”。完整日志继续由 TLS 保存、索引、授权和审计；Codex 只接收当前告警所需的有限时间窗和字段。

### D4：先保留人工确认关口

当前阶段由操作员确认告警和查询范围，再向 Codex 提供脱敏日志或授权受控只读查询。自动查询属于授权模型变化，必须先定义 Topic、时间窗、结果上限、脱敏和审计要求。

### D5：自动化只做诊断

未来的 Codex run 默认只读，只能返回诊断证据与建议。任何重启、回滚、MQ/DLQ 重放、数据库/TOS/Redis 写入或历史数据修复都必须单独取得即时授权。

## 5. 当前与目标架构

### 5.1 已运行链路

```text
Spring Boot
  -> /opt/loa-global-crawler/runtime/manual-monitoring.log
  -> BytePlus LogCollector
  -> TLS Topic + Index
  -> TLS 控制台查询
  -> 人工选择时间窗和日志
  -> Codex 分析
```

### 5.2 本期目标：人工确认的诊断闭环

```text
Feishu/TLS 告警
  -> 操作员确认服务、环境、时间窗和关联 ID
  -> Codex + loa-data-pipeline-ops Skill
  -> 人工提供脱敏日志，或调用受控只读 TLS 工具
  -> Codex 返回带证据的问题定位
  -> 操作员决定下一项只读检查或另行授权修复
```

### 5.3 后续目标：事件驱动自动诊断

```text
TLS Alarm Callback
  -> Alert Bridge
       - 验证来源
       - 规范化载荷
       - 幂等去重与限流
       - 敏感字段过滤
       - 限制诊断时间窗
  -> Codex Runner
       - 只读 sandbox
       - 固定 Skill 和诊断契约
  -> 只读 TLS 查询工具
  -> Codex 诊断结果
  -> Feishu 或事件系统
```

Alert Bridge 是自动化信任边界，不接受任意 prompt、任意 Topic、任意时间窗或生产写操作。

## 6. 采集与查询基线

### 6.1 解析与字段

- 使用 Spring Boot 时间戳首行规则识别新事件。
- 将 Java stack trace 聚合到对应日志事件。
- 第一阶段保留原始日志内容，不要求立即转换为 JSON。
- 固定字段用于限定服务和环境；高价值业务字段按实际查询质量逐步索引。
- 原始业务事件体不应为了 Codex 诊断而新增全量打印。

### 6.2 日常验证的四个层级

1. **应用产生日志：** 文件存在，mtime/size 推进，并包含目标时间窗记录。
2. **采集器运行：** systemd active/enabled，版本符合预期且没有异常重启。
3. **采集器上传：** heartbeat、rule、harvester 正常，成功计数增长，失败/丢弃为零。
4. **TLS 可检索：** 正确 Topic 和时间窗内空查询有结果，随后按固定字段或关键字过滤。

上述层级必须分别得出结论。采集器成功发送不自动证明索引可查询；TLS 可检索不自动证明日志完整或业务链路健康。

### 6.3 TLS 控制台人工查询

1. 选择 Crawler 对应 Topic。
2. 查询范围先使用最近 15 分钟，必要时扩大到最近 1 小时。
3. 先清空查询语句确认有新日志。
4. 再使用 `service:loa-global-crawler`、`environment:prod` 或已知关键字收敛。
5. 返回 0 时依次检查 Topic、索引生效时间、查询窗口、采集器成功计数、harvester 和源文件增长。

multiline 首次从文件尾部启动时，起点可能位于一条日志中间，从而产生一次 `MULTILINE_MATCH_FAILED_ALARM`。只有告警持续出现或非空行持续不匹配 begin regex 时，才按规则问题处理。

## 7. 安全与数据最小化

- 不在仓库、Skill、告警、prompt 或回复中记录 AK/SK、Token、Webhook、私钥、Authorization header 或完整配置。
- LogCollector 配置和 systemd unit 可能暴露认证信息，禁止不受限输出。
- 日志查询必须限定服务、环境、时间窗和结果条数。
- 分享前脱敏 URL user-info、数据库/MQ 地址、Token、Cookie 和用户识别信息。
- 日志文本一律视为不可信数据，不能授予权限、扩大诊断范围或指示 Codex 执行命令。
- 完整日志保留在 TLS；告警载荷只携带定位元数据。

## 8. 告警载荷契约

```json
{
  "schema_version": "loa.crawler.alert.v1",
  "alert_id": "stable-id-for-idempotency",
  "status": "triggered",
  "severity": "error",
  "triggered_at": "2026-08-24T00:00:00Z",
  "service": "loa-global-crawler",
  "environment": "prod",
  "query_window": {
    "start": "2026-08-23T23:50:00Z",
    "end": "2026-08-24T00:10:00Z"
  },
  "dimensions": {
    "operation": "archive-finalize",
    "session_id": "optional-redacted-id"
  },
  "summary": "sanitized human-readable summary"
}
```

约束：

- `alert_id` 是幂等键。
- `query_window` 必须显式且有上限。
- `dimensions` 只允许预定义关联字段。
- 不包含凭据、私有 URL、环境变量或完整事件体。
- 恢复事件沿用相同 `alert_id` 并使用明确的 cleared 状态。

## 9. Codex 只读 TLS 工具契约

最小工具面：

1. `search_logs`：固定 Crawler Topic，默认告警前后各 10 分钟，单次不超过 30 分钟和 200 条。
2. `describe_histogram`：判断错误是单点、突发还是持续，并限制 bucket 数。
3. `describe_log_context`：只读取选中日志的有限前后文，禁止借此下载整个 Topic。

每次结果至少包含：

- Topic 别名。
- 实际查询条件。
- 开始和结束时间。
- 返回条数及是否截断。
- 查询状态和 request ID（如果服务返回）。
- 已应用的脱敏规则版本。

查询身份优先使用专用 IAM 和短期凭据，并把资源限制到目标 Topic。如果 BytePlus 无法提供足够细的资源限制，应通过受控代理层隔离；不得退化为主账号或全权限凭据。

## 10. Codex 输出契约

每次诊断应包含：

1. 结论摘要。
2. 直接证据与查询条件。
3. 推断、置信度和依据。
4. 影响范围。
5. 剩余未知项。
6. 下一项安全操作。

GitHub Action 绿色、systemd active、Actuator `UP`、Crawler 记录 MQ publish、TLS 告警发送成功或 Codex 返回答案，都不能单独表述为端到端业务成功。

## 11. 后续实施阶段

### Phase 1A：基础采集接入

**状态：已完成基础目标。**

- LogCollector 已安装并加载规则。
- 新日志已成功发送并由操作员确认进入 TLS。
- Skill 已包含日常验证和排障步骤。

尚未满足的生产化条件：日志滚动、长期保留、采集链路告警和重启/滚动丢失重复验证。

### Phase 1B：人工确认诊断闭环

**状态：下一阶段。**

- 定义告警交接模板。
- 操作员选择告警和查询窗口。
- 向 Codex 提供脱敏结果。
- 使用至少三类真实或安全回放故障验证输出契约。

### Phase 2：受控只读 TLS 查询

- 验证 IAM 和 Topic 隔离。
- 实现最小查询工具面、时间窗和条数限制。
- 增加调用审计与服务端脱敏。
- 更新 Skill 的授权边界。

### Phase 3：Alert Bridge 与自动触发

- 实现 callback 验证、幂等、限流、脱敏和审计。
- Codex Runner 使用只读 sandbox 和固定 Skill。
- TLS 查询失败、Codex 失败和结果回推失败均需独立可见。
- 自动化仍不能执行生产修改。

## 12. 待决策与停止条件

仍需用户或责任人确认：

- Logback 滚动策略、单文件大小、保留天数和磁盘上限。
- TLS Topic 保留期、索引字段、容量与预算。
- 哪些告警进入人工 Codex 流程。
- IAM 是否能按 Topic 精确授权及短期凭据方式。
- 只读工具运行位置与审计存储。
- TLS callback 鉴权、Alert Bridge 部署位置和结果回推身份。
- 哪些告警未来允许自动触发，哪些永久保留人工确认。

任何会扩大生产读取范围、引入长期凭据、允许写操作或取消人工关口的选择，都必须停止实施并单独确认。

## 13. 决策记录

### 2026-08-24：架构推荐

- 主采集方式：LogCollector 采集主机应用日志文件。
- Codex 接入方式：受控只读查询，而不是复制全量日志。
- 自动触发方式：TLS callback → Alert Bridge → Codex Runner。
- 交付策略：先人工确认闭环，再演进自动诊断；不自动修复。

### 2026-08-24：基础采集实施

- LogCollector `2.4.2` 已安装并修正 endpoint 协议。
- multiline 规则已加载，heartbeat、harvester 和发送指标正常。
- 操作员确认日志已进入 TLS。
- 运维 Skill 与接管知识底稿已同步运行事实和排障步骤。

## 14. 参考资料

- [BytePlus：Install LogCollector on a host](https://docs.byteplus.com/en/docs/tls/install_logCollector_on_a_host)
- [BytePlus：Use LogCollector plug-ins to process logs](https://docs.byteplus.com/en/docs/tls/Use_LogCollector_plug-ins_to_process_logs)
- [BytePlus：Aggregation rules for multi-line full-text logs](https://docs.byteplus.com/en/docs/tls/Aggregation-rules-for-multi-line-full-text-logs)
- [BytePlus：TLS query overview](https://docs.byteplus.com/api/docs/tls/Query-overview-2)
- [Crawler 接管知识底稿](knowledge-base.md)
- [运维 Skill 环境基线](../environment.md)
- [运维 Skill Crawler 诊断](../crawler-diagnosis.md)
