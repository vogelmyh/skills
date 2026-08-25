# Data Gateway 日志接入 BytePlus TLS 指南

- **状态：** PROPOSED（尚未在线实施或验证）
- **最后更新：** 2026-08-24
- **适用组件：** `loa-data-gateway`
- **目标主机：** `ECS-Uat-Test-Back`
- **文档性质：** 人工配置指南、风险边界与验收基线

## 1. 结论

Gateway 应复用 Crawler 已验证的“主机文件 → BytePlus LogCollector → TLS Topic”架构，但不能照搬 Crawler 的 multiline 解析规则：Gateway 普通日志由 Go `slog.JSONHandler` 生成，每行是一个 JSON 对象，应使用 JSON 采集模式。

首期只接入两个普通应用日志文件：

- `main`：`/www/go-server/loa-data-gateway/logs/loa-data-gateway.log`
- `test`：`/www/go-server/loa-data-gateway-test/logs/loa-data-gateway-test.log`

首期不接入以下完整 MQ 事件日志：

- `main`：`/var/log/loa-data-gateway/loa-data-gateway-event.log`
- `test`：`/var/log/loa-data-gateway-test/loa-data-gateway-event.log`

事件日志每行的 `.event` 都可能包含完整 RabbitMQ payload、用户和直播互动数据。把它们送入普通 Topic 会扩大访问、索引、告警和 Codex 查询的敏感数据面。

## 2. 已确认事实与待核验项

静态代码和部署脚本已经确认：

- `main@f583e90a1e7428fa78737d2719a4c3371eea9da6` 使用 `slog.NewJSONHandler(os.Stdout, nil)` 输出普通日志。
- systemd 将 stdout/stderr 追加到上述普通日志文件。
- 普通日志和事件日志均按天或达到 `100M` 时轮转，保留 14 代，启用 `compress`、`delaycompress` 和 `copytruncate`。
- `main` 和 `test` 位于同一台 ECS，竞争同一 RabbitMQ queue 并共享生产依赖；`test` 不是隔离环境。

以下信息仍须由操作员在 BytePlus/主机上核验，不能从 Crawler 状态推断：

- Gateway ECS 所在 Region，以及应使用的 TLS Project、Topic 和 endpoint。
- Gateway 主机是否已安装 LogCollector、版本、服务状态和配置文件权限。
- LogCollector 实际报告的主机 IP、host group heartbeat 和规则下发状态。
- 两个普通日志文件的实际权限、日增量、最大单行大小和敏感字段分布。
- Topic 保留期、索引成本、告警规则和 IAM 负责人。

## 3. 推荐资源与规则

名称可按团队规范调整，但语义不要改变：

- Host group：`loa-data-gateway-ecs`
- 普通日志 Topic：`loa-data-gateway-application`
- Main 规则：`loa-data-gateway-main-application`
- Test 规则：`loa-data-gateway-test-application`

两条规则都写入普通日志 Topic，但必须使用不同的精确路径和固定字段。

Main 固定字段：

```text
component=gateway
service=loa-data-gateway
instance=main
environment=production-shared
log_type=application
```

Test 固定字段：

```text
component=gateway
service=loa-data-gateway-test
instance=test
environment=production-shared
log_type=application
```

`environment=production-shared` 是安全语义：它提醒查询者，`test` 仍消费生产消息并使用生产依赖。不要写成 `environment=test` 后再据此放宽权限或告警。

## 4. 人工配置步骤

### 4.1 只读预检

操作员通过 BytePlus 控制台和获批密钥进入目标主机后，执行：

```bash
systemctl is-active loa-data-gateway.service
systemctl is-active loa-data-gateway-test.service
stat -c '%a %U:%G %s %y %n' \
  /www/go-server/loa-data-gateway/logs/loa-data-gateway.log \
  /www/go-server/loa-data-gateway-test/logs/loa-data-gateway-test.log
namei -l /www/go-server/loa-data-gateway/logs/loa-data-gateway.log
namei -l /www/go-server/loa-data-gateway-test/logs/loa-data-gateway-test.log
tail -n 100 /www/go-server/loa-data-gateway/logs/loa-data-gateway.log | jq -e . >/dev/null
tail -n 100 /www/go-server/loa-data-gateway-test/logs/loa-data-gateway-test.log | jq -e . >/dev/null
```

`jq` 命令只验证逐行 JSON，不回显日志。若失败，先确认是否混入部署脚本/旧版本的非 JSON 行；不要直接切换成 multiline 规则掩盖格式混杂。

检查 LogCollector 是否已存在：

```bash
systemctl is-active logcollectord.service
systemctl is-enabled logcollectord.service
systemctl show logcollectord.service \
  --property=User,Group,ActiveState,SubState,NRestarts,ExecMainStartTimestamp \
  --no-pager
/usr/local/logcollector/logcollector -v
```

若未安装，使用 TLS 控制台针对目标 Region 生成的官方安装流程。禁止把安装命令中的 AK/SK、配置文件或完整 systemd unit 复制到文档、聊天或工单。

### 4.2 Region、endpoint 与 host group

1. 在 BytePlus 控制台确认 Gateway ECS Region。
2. 在同 Region 创建或选择 TLS Project 和普通日志 Topic。
3. 创建 IP 型 host group，并使用 LogCollector 实际报告的 IP；对 ECS 通常是私网 IP，但以 heartbeat 页面为准。
4. 等待 host heartbeat 为 normal 后再创建规则。
5. 如果 Region 确认为 `ap-southeast-1` 且使用 LogCollector `2.4.2`，endpoint 候选为 `https://tls-ap-southeast-1.ibytepluses.com`；必须包含 `https://`。其他 Region 使用控制台提供的同 Region endpoint，不能照抄 Crawler 值。

不要输出 `/usr/local/logcollector/etc/logcollector.yml`。它可能包含认证信息；只核验文件权限应为严格的 root-only（例如 `600 root:root`）。

### 4.3 创建 Main 普通日志规则

在 TLS 控制台选择正确 Project/Topic 与 host group，然后配置：

- Rule name：`loa-data-gateway-main-application`
- Collection path：`/www/go-server/loa-data-gateway/logs/loa-data-gateway.log`
- Collection mode：JSON
- Time：首期使用采集时间，同时保留 JSON 内的 `time` 字段；验证 RFC3339Nano 解析兼容性后再决定是否用应用时间覆盖采集时间。
- Policy：增量采集（`TailFiles=true`）
- Initial tail：`10 KiB`
- Hostname field：启用
- Fixed fields：使用第 3 节 Main 字段
- Raw duplicate upload：关闭，避免 JSON 解析结果之外再保存一份原始副本

只匹配当前活动文件，不使用 `*.log*`，不采集 `.1` 或 `.gz`。现有 `copytruncate` 轮转在切换窗口仍可能造成少量重复或遗漏，首次上线后应专门观察一次轮转边界。

### 4.4 创建 Test 普通日志规则

配置与 Main 相同，但改为：

- Rule name：`loa-data-gateway-test-application`
- Collection path：`/www/go-server/loa-data-gateway-test/logs/loa-data-gateway-test.log`
- Fixed fields：使用第 3 节 Test 字段

不要把两个路径放进同一条规则，否则不能可靠注入不同的 `instance`/`service` 固定字段。

### 4.5 索引与保留

普通日志优先为以下字段建立 key-value 索引：

```text
time level msg component service instance environment log_type
commit queue event_id event_type manifest_path part job_id redelivered
```

先按实际样本确认字段是否存在，再建立索引。需要聚合的字段才启用 statistics。全文索引可用于普通日志的临时故障搜索，但应先评估费用和错误字符串中的敏感内容；key-value 索引通常更可控。

Topic 保留期必须由数据量、故障回溯窗口、费用和合规共同决定。本指南不把 Crawler 的保留设置假定为 Gateway 的既定值。

## 5. 验收顺序

四个层级分别验收，不能合并成一句“日志接入成功”：

1. **应用产生日志：** 两个普通日志文件存在、为逐行 JSON，并在预期活动窗口推进。
2. **采集器运行：** `logcollectord.service` 为 active/enabled，版本正确且无异常重启。
3. **采集器上传：** heartbeat normal，两条规则/harvester 已加载，成功请求和日志计数增长，失败/丢弃为零。
4. **TLS 可检索：** 正确 Topic 和时间窗内空查询有结果；按 `environment:production-shared` 与 `instance:main|test` 能分别查询。

主机只读检查：

```bash
systemctl is-active logcollectord.service
systemctl is-enabled logcollectord.service
systemctl show logcollectord.service \
  --property=ActiveState,SubState,NRestarts,ExecMainStartTimestamp \
  --no-pager
/usr/local/logcollector/logcollector -v
stat -c '%s %y %n' \
  /www/go-server/loa-data-gateway/logs/loa-data-gateway.log \
  /www/go-server/loa-data-gateway-test/logs/loa-data-gateway-test.log
```

查看采集器日志时，只取当前时间窗并筛选 heartbeat、rule、harvester、成功/失败/丢弃计数以及 `unsupported protocol scheme`。分享前脱敏 `secret_id`、`secret_key`、AK-like token 和 Authorization header。

首次 `TailFiles` 从文件尾部开始时，10 KiB 起点可能落在一行 JSON 中间，允许出现一次解析失败；如果新追加的完整行持续解析失败，才判定规则或源日志格式异常。

## 6. 查询与告警建议

TLS 控制台先选普通日志 Topic，时间窗使用最近 15 分钟，必要时扩大到 1 小时：

```text
environment:production-shared AND instance:main
environment:production-shared AND instance:test
level:ERROR
msg:"RabbitMQ consumer disconnected; reconnecting"
msg:"import rejected to dead-letter exchange"
```

具体语法以 Topic 当前索引配置为准。先用空查询证明 Topic/时间窗有数据，再逐步增加字段过滤。

可建立的首批告警包括：

- `level=ERROR` 在短时间窗出现。
- RabbitMQ consumer 断开/重连。
- 导入被拒绝到 DLQ。
- LogCollector host heartbeat 异常、持续上传失败或丢弃计数增长。

“一段时间无应用日志”不能单独作为服务宕机告警，因为 Gateway 在没有消息时可能保持安静；必须结合 systemd、RabbitMQ 流量/积压和 collector heartbeat。

## 7. 完整 MQ 事件日志的单独关口

只有在普通日志无法满足已定义的诊断需求，并完成数据负责人、IAM、保留期、费用和 Codex 查询范围审批后，才能考虑采集事件日志。最低要求：

- 使用与普通日志完全分离的 Topic。
- 使用独立、最小权限的查询身份，不授予普通值班角色或 Codex 默认身份。
- 设置最短合规保留期，默认不启用广泛全文索引。
- 明确禁止告警载荷附带完整 `.event`。
- 先验证 TLS masking/字段白名单，再决定是否保留原始 payload。
- Main/Test 仍使用两条精确路径规则，不匹配轮转文件。

未满足这些条件时继续采用服务器端 `jq` 投影，把限定字段和最多 20 条脱敏结果交给诊断者。

## 8. 停止与回退条件

遇到以下任一情况立即暂停规则，不继续扩大范围：

- Topic、Region 或 host group 与目标主机不一致。
- 普通日志样本含未受控凭据、Authorization header 或超出预期的用户 payload。
- 规则误匹配事件日志、轮转日志或其他服务文件。
- LogCollector 明显影响 Gateway CPU、内存、磁盘或 IO。
- 失败/丢弃计数持续增长，或 JSON 解析持续失败。
- Main/Test 固定字段无法正确区分。

暂停或解绑采集规则不会删除已写入的 TLS 数据。若敏感数据已进入 Topic，应立即限制查询权限，并由 TLS 管理员按合规流程处理保留或删除；不能只停 collector 后宣称风险已消除。

## 9. 参考资料

- [LogCollector collection rule management](https://docs.byteplus.com/en/docs/tls/logcollector_collection_rule_management)
- [Host group overview](https://docs.byteplus.com/en/docs/tls/host_group_overview)
- [LogCollector plug-ins overview](https://docs.byteplus.com/en/docs/tls/plug-ins_Overview)
- [Query and analysis process](https://docs.byteplus.com/en/docs/tls/Query-and-analysis-process)
- [FAQ about query and analysis of JSON logs](https://docs.byteplus.com/en/docs/tls/FAQ-about-the-query-and-analysis-of-JSON-logs)
- [Troubleshoot abnormal host log collection](https://docs.byteplus.com/en/docs/tls/How-to-troubleshoot-abnormal-log-collection-on-the-host-machine)
