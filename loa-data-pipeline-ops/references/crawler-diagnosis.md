# Crawler 诊断

代码仓库：[Lighthunter-PTE-ltd/loa-glabal-crawler](https://github.com/Lighthunter-PTE-ltd/loa-glabal-crawler)。当前快照记录的告警实现为 [`prod@f503869ce90b5f389ced6297f052e159787dbea4`](https://github.com/Lighthunter-PTE-ltd/loa-glabal-crawler/tree/f503869ce90b5f389ced6297f052e159787dbea4)；使用本地 clone 时先核验 origin，实际运行的 JAR 仍必须单独核验。

## 人工日志协作

人工操作员使用获批密钥进入 BytePlus 和生产服务器后，只提供限定时间范围的必要命令。常用只读命令包括：

```bash
systemctl status loa-global-crawler.service --no-pager
journalctl -u loa-global-crawler.service --since '<start>' --until '<end>' --no-pager
tail -n 300 /opt/loa-global-crawler/runtime/manual-monitoring.log
curl --fail --silent http://127.0.0.1:8080/actuator/health
```

对于大型日志，应按已校验的 streamer ID、room ID、session ID、event ID、archive prefix、告警标题和时间窗口过滤。优先使用 `rg`，不可用时再用 `grep`。绝不索取 `/etc/loa-global-crawler/feishu-alerting.env`、profile 凭据值、`printenv` 或不受限的日志转储。

## BytePlus TLS 日志采集

2026-08-24 已在生产 Crawler 主机安装并验证 LogCollector。环境基线、版本、规则与已证明的结论见 [environment.md](environment.md)。该记录是运行快照，不替代当前只读核验。

### 日常验证顺序

先区分四个层级，避免把其中一层正常表述为整条日志链路正常：

1. **应用产生日志：** `/opt/loa-global-crawler/runtime/manual-monitoring.log` 存在，mtime/size 持续推进，并包含目标时间窗口内的新记录。
2. **采集器运行：** `logcollectord.service` 为 `active`、`enabled`，版本符合预期且没有异常重启。
3. **采集器上传：** heartbeat 正常、rule/harvester 数为 1，成功请求/日志计数增加，失败和丢弃计数为 0。
4. **TLS 可检索：** 在正确 Topic 中、覆盖日志产生时间的查询窗口内，空查询可以返回日志；随后再按固定字段或关键字过滤。

人工操作员可在生产主机执行以下只读检查：

```bash
systemctl is-active logcollectord.service
systemctl is-enabled logcollectord.service
systemctl show logcollectord.service --property=ActiveState,SubState,NRestarts,ExecMainStartTimestamp --no-pager
/usr/local/logcollector/logcollector -v
stat -c '%s %y %n' /opt/loa-global-crawler/runtime/manual-monitoring.log
curl --fail --silent http://127.0.0.1:8080/actuator/health
```

查看采集器日志时，只读取当前时间窗口内的少量记录，并优先筛选以下指标或错误信号：`HeartbeatStatus`、`HarvesterNum`、`RuleNum`、`SendSuccessfulReqs`、`SendFailReqs`、`SendSuccessfulLogCount`、`SendDropLogCount`、`unsupported protocol scheme`。分享输出前必须脱敏 `secret_id`、`secret_key`、AK-like token、Authorization header 和其他凭据；禁止输出完整 LogCollector 配置、systemd unit 或不受限日志。

### TLS 控制台验证

1. 选择 Crawler 对应 Topic，时间范围先设为最近 15 分钟；若安装、索引或规则生效较早，扩大到最近 1 小时。
2. 清空检索语句并刷新。空查询有结果后，再使用 `service:loa-global-crawler`、`environment:prod` 或已知日志关键字缩小范围。
3. 如果仍为 0，确认 Topic 选择正确、查询窗口覆盖采集器成功发送的时间，并检查全文/键值索引的启用状态与生效时间。
4. 采集器已有成功发送计数但 TLS 仍不可检索时，优先定位 Topic/索引/时间窗口；应用日志未增长时，优先定位 Crawler；harvester 为 0 时，优先定位规则匹配、文件路径和读取权限。

multiline 采集首次从文件尾部启动时，可能因起点位于一条日志中间而出现一次 `MULTILINE_MATCH_FAILED_ALARM`。只有告警持续出现，或抽样发现非空行持续不匹配 begin regex 时，才按 multiline 规则问题处理。规则启用了 `TailFiles`，不能把首次接入后看不到全部历史日志视为采集故障。

对日志查询结论使用准确表述：成功发送计数证明 LogCollector 已向 TLS 发送；TLS 检索命中证明指定 Topic 和索引可查询；二者都不单独证明日志完整性、告警覆盖或 Crawler 业务数据路径健康。

## 告警投递语义

当前唯一的通知渠道是带签名的 Feishu 自定义机器人：

- 运行时告警使用一个 daemon worker 和容量为 64 的内存队列；提交为非阻塞操作。
- 同一进程内，同一内部键从告警成功入队起抑制五分钟。发送失败后仍继续抑制；重启会清除抑制状态；不同实例之间不共享抑制状态。
- 投递超时为五秒，且没有重试、持久化、DLQ 或第二渠道。队列已满和投递失败只记录在应用日志中。
- 关闭时最多等待六秒排空队列。
- 启动失败会在 Spring 外同步发送且不去重；systemd 重启循环可能导致重复告警。
- Feishu 中不显示内部键。显示时间是发送时间，不一定是首次故障时间。
- 消息只包含选定标识符，不包含原始事件体，并执行通用的密钥/URL 脱敏；但仍含有可识别的 streamer/GUID/room/session/event/battle/archive 字段，只能在获批场景中使用。

## 告警映射

错误（ERROR）：

- `service-startup-failed`：Spring 启动失败。字段：environment、error type、error。
- `schedule-poll-failed`：已启用的 Battle 日程请求/解析失败。生产 profile 默认关闭此功能，除非运行时覆盖配置。
- `status-worker:<streamer>`：live-status worker 意外退出。取消/关闭不触发告警；随后会尽可能恢复重试节奏。
- `cluster-coordination-unavailable`：Redis due-target claim、lease acquire 或 lease renew 失败。检查 `operation` 和 streamer。
- `archive-event:<session-or-streamer>:<event-type>`：普通事件归档写入失败。检查 streamer、room、session、event type、archive prefix 和 error。
- `archive-finalize:<session-or-streamer>`：结束事件/final manifest 写入失败；pending session 会保留以便重试。
- `mq-publish:outside-battle`：Battle MQ 配置或同步发布失败。
- `mq-publish:monitor:<event-type>`：Monitor routing identity/configuration 或同步发布失败。
- `mq-publish:legacy-live-ended`：Legacy routing identity、confirmed archive path、配置或同步发布失败。

警告（WARNING）：

- `target-sync:incremental` 和 `target-sync:refresh`：目标数据库同步降级；诊断共享故障边界后，等待下一次计划尝试。
- `identity-lookup:redis` 和 `identity-lookup:database`：API 目标身份解析降级。Redis 失败时回退到 DB；DB 失败时继续按外部目标处理，可能改变身份/归档语义。
- `cluster-coordination-degraded`：Redis target state、next-probe persistence 或 GUID index 操作降级。检查 `operation`。

MQ publisher 配置/网络错误会告警并抛出异常。缺少 Monitor/Legacy routing identity 或 Legacy confirmed path 时会告警并跳过该消息。如果 RabbitMQ 发布已禁用，则不告警且不执行任何操作。

## 重要盲区

- LogCollector heartbeat 只监测采集器到 TLS 的连接，不是 Crawler 应用 heartbeat。当前仍没有独立的主机/应用进程监控、吞吐量/延迟 SLO、无事件检测器、恢复通知或第二告警渠道监控。
- Euler 401/403/429/5xx、request-budget/backoff、普通 TikTok 断开/连接重试和持续 `UNKNOWN` 大多只记录日志。
- 归档 `prepareSession`、定期/关闭 flush、retained-event retry 和 pre-session-buffer eviction 中存在只记录日志的路径。
- RabbitMQ 使用同步 `basicPublish`，没有 publisher confirm、mandatory-return 或下游业务 ACK 证明。“已发布”不能证明消息已路由或已消费。
- Redis unavailable/degraded、identity source 等通用键，可能把不同操作/streamer 的告警共同抑制五分钟。
- 告警文本缺少 commit SHA、deployment run、host IP 和 trace ID。
- Gift Chat、BytePlus LLM、Euler OAuth 和 chat send 大多只记录日志。

没有告警不能证明系统健康。Feishu 投递成功也不能证明覆盖了所有故障类型。

## 诊断路径

### 主播未被监控

按以下顺序检查：

1. 目标存在于预期来源中，并具有正确的 TikTok/LOA 身份。
2. Redis registry/due queue 包含该目标，且某个节点可以 claim/renew lease。
3. next probe 正常推进。
4. Euler 状态以及共享 backoff/budget 未卡住。
5. 已确认的直播状态能够触发 TikTok LIVE 连接。

### 有直播但没有 TOS

检查 active connection、archive-session 创建、正确的 identity/room、直播期间的 part 上传、manifest 更新、bucket/profile、TOS 错误，以及只记录日志的定期 flush 路径。不要只等到 `live.ended` 才判断归档数据是否应已存在。

### 收到 MQ 但 manifest 不存在

将 Legacy MQ 中准确的 `manifestPath` 直接作为 TOS object key。核验 confirmed archive snapshot，并按 room ID 搜索重复目录。绝不能根据时间或 session 猜测重建路径。

### TOS 正常但 Gateway 未处理

区分 Legacy `live.ended` 和 Monitor `live.ended`。应按 session ID 关联，不能按它们各自独立的 event ID 关联。检查 Crawler 同步发布证据、exchange/binding、queue/DLQ、两个 Gateway consumer、准确的 manifest path，以及数据库幂等证据。

### 告警本身疑似失效

在不打印配置值的前提下，检查两个 Feishu 配置是否均已注入；再从应用日志中搜索 queue-full、submission、worker 或 delivery failure。workflow 的存在性检查不能证明 HTTPS 可达、签名正确或机器人实际投递成功。
