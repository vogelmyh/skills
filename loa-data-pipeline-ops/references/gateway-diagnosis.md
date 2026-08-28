# Gateway 诊断

代码仓库：[Lighthunter-PTE-ltd/loa-data-gateway](https://github.com/Lighthunter-PTE-ltd/loa-data-gateway)。2026-08-21 已复核的静态代码快照为 [`main@f583e90a1e7428fa78737d2719a4c3371eea9da6`](https://github.com/Lighthunter-PTE-ltd/loa-data-gateway/tree/f583e90a1e7428fa78737d2719a4c3371eea9da6)；使用本地 clone 时先核验 origin，采取操作前还应核验更新的仓库和运行时状态。

## 生产只读日志访问

当前请求明确要求 Gateway 生产诊断时，先按 [access-channel.md](access-channel.md) 将逻辑目标 `gateway-shared` 绑定到当前使用者已获批的 SSH、BytePlus 会话或专用只读工具。`ECS-Uat-Test-Back` 没有公网 IP，不能把私网地址当成任意环境可直连的入口。Main/Test 使用同一访问目标但对应不同 systemd 服务和日志路径；Skill 不要求为它们设置两个固定 alias。不得读取凭据、`.env` 或执行任何状态变更。

Main：

```bash
systemctl status loa-data-gateway.service --no-pager
tail -n 300 /www/go-server/loa-data-gateway/logs/loa-data-gateway.log
/www/go-server/loa-data-gateway/loa-data-gateway --version
```

Test：

```bash
systemctl status loa-data-gateway-test.service --no-pager
tail -n 300 /www/go-server/loa-data-gateway-test/logs/loa-data-gateway-test.log
/www/go-server/loa-data-gateway-test/loa-data-gateway-test --version
```

完整 MQ 事件日志：

- Main：`/var/log/loa-data-gateway/loa-data-gateway-event.log`。
- Test：`/var/log/loa-data-gateway-test/loa-data-gateway-event.log`。

这些文件可能含有完整的用户/直播 payload。应按时间和已校验的 eventId、manifestPath、roomId、sessionId 或 part 名称过滤；限制上下文并脱敏后才能分享。绝不索取完整事件文件、`.env`、凭据或完整 MQ 消息体。

事件日志的每一行都在 `.event` 下包含完整 MQ 消息体，因此直接输出 `rg` 结果可能泄露消息体。优先使用 JSON 投影。对于已校验的纯数字 room ID，应先检查当前文件，且最多返回 20 条记录：

```bash
ROOM_ID='7340000000000000000'
jq -c --arg rid "$ROOM_ID" '
  select(((.event.data.roomId? // "") | tostring) == $rid)
  | {
      time,
      exchange,
      routing_key,
      message_id,
      redelivered,
      event_id: .event.eventId,
      event_type: .event.eventType,
      room_id: .event.data.roomId,
      session_id: .event.data.sessionId,
      manifest_path: .event.data.manifestPath
    }
' /var/log/loa-data-gateway/loa-data-gateway-event.log | head -n 20
```

由于两个实例竞争消费，必须单独使用 test 路径。如果 `jq` 不可用，只返回文件名和准确匹配数量，绝不能返回匹配的事件行。日志每天或达到 100 MB 时轮转，保留 14 代并压缩。先搜索当前文件，再搜索未压缩的轮转文件；随后仅使用返回文件名的 `zgrep -l -F` 确认相关压缩代，再对准确选定的路径执行投影，例如 `gzip -cd -- '/var/log/loa-data-gateway/loa-data-gateway-event.log.2.gz' | jq ...`。不得在不说明理由的情况下扩大时间/文件范围。

## BytePlus TLS 日志采集

2026-08-24 已形成 Gateway TLS 拟配置，但尚无 Gateway 主机安装、规则下发或 TLS 查询的运行时证据。不要把 Crawler 已接通的状态外推到 Gateway。

首期范围：

- Main 普通日志：`/www/go-server/loa-data-gateway/logs/loa-data-gateway.log`。
- Test 普通日志：`/www/go-server/loa-data-gateway-test/logs/loa-data-gateway-test.log`。
- 两者都是逐行 JSON，使用 JSON 采集模式；Main/Test 必须使用两条精确路径规则。
- 固定字段统一使用 `environment=production-shared`、`component=gateway`、`log_type=application`，再按 `instance=main|test` 与准确的 `service` 区分。
- 启用 `TailFiles`，建议初始尾部 `10 KiB`，不匹配轮转文件。首次起点落在一行中间时允许出现一次 JSON 解析失败；新追加完整行持续失败才是异常。
- 完整 MQ 事件日志首期不接入 TLS。只有完成独立 Topic、最小 IAM、最短保留期、masking/字段白名单和数据负责人审批后才可另行考虑。

具备获批访问通道时，可执行以下只读检查：

```bash
systemctl is-active logcollectord.service
systemctl is-enabled logcollectord.service
systemctl show logcollectord.service --property=User,Group,ActiveState,SubState,NRestarts,ExecMainStartTimestamp --no-pager
/usr/local/logcollector/logcollector -v
stat -c '%s %y %n' \
  /www/go-server/loa-data-gateway/logs/loa-data-gateway.log \
  /www/go-server/loa-data-gateway-test/logs/loa-data-gateway-test.log
tail -n 100 /www/go-server/loa-data-gateway/logs/loa-data-gateway.log | jq -e . >/dev/null
tail -n 100 /www/go-server/loa-data-gateway-test/logs/loa-data-gateway-test.log | jq -e . >/dev/null
```

验收必须分四层：应用文件增长且为逐行 JSON；collector active/enabled；heartbeat/rule/harvester 与成功/失败/丢弃计数正常；正确 Topic/时间窗中可按 `instance` 分别检索。无应用日志不能单独证明服务宕机，仍需结合 systemd、RabbitMQ 流量/积压和 collector heartbeat。

若 Region 确认为 `ap-southeast-1` 且版本为 LogCollector `2.4.2`，endpoint 应包含完整 `https://`；其他 Region 使用控制台给出的同 Region endpoint。禁止输出 collector 配置内容。若误采事件日志或发现凭据/完整用户 payload，立即暂停规则并限制 Topic 权限；停采不会删除已经上传的数据。

## RabbitMQ 与处理语义

- Topic exchange：`openclaw_skill_topic_exchange`。
- Binding：`user.pk.invitation.response.#`。
- 持久化 queue：`loa_data_gateway_live_ended`。
- 持久化 DLQ：`loa_data_gateway_live_ended_dlq`。
- 每个实例使用两个 worker，prefetch 为 2；`main` 和 `test` 竞争消费相同消息。
- worker 处理前会记录完整 MQ 消息体。

处理结果：

- JSON 无效、缺少关键字段或 archive-contract 不匹配：永久失败，NACK 且不 requeue，随后进入 DLQ。
- 非 `live.ended` 事件：ACK 并忽略。
- 临时 TOS/PostgreSQL/unfinished-manifest 失败：进程内最多尝试五次并执行 backoff，随后进入 DLQ。
- 关闭中断：NACK 并 requeue。
- ACK/NACK 失败或 consumer panic：触发告警并重建 RabbitMQ consumer 连接；当前 worker 不会确认发生 panic 的消息。

DLQ 是恢复边界，不能证明没有写入任何数据。

## TOS 与 PostgreSQL 约束

导入前，Gateway 会校验 MQ/manifest/part identity contract、completed manifest、part count、安全的相对 object key、GUID/room/session 一致性、part metadata 和解码后的事件总数。

每个 part 独立提交。在同一个 part 内，production 和 test event schema 通过一个事务写入。如果后续 part 失败，较早的 part 仍保持已提交状态。Event ID 冲突处理为重放提供幂等性，但事件总数校验发生在 part 提交之后。

不能根据单个 part 的双 schema 原子性，推断整个 manifest 具有原子性。

## 用户、头像与手动导入边界

- User snapshot 和 avatar-job 失败发生在事件导入之后，会单独告警，不回滚事件，也不改变 MQ ACK。
- User/avatar 工作使用独立的资源池和时间预算；avatar job 会持久化并重试。
- `POST /internal/v1/manifest-imports` 只监听实例的回环端口，同一时刻只接受一个内存 job；由于仅限回环访问，因此没有应用层认证。
- 手动导入复用幂等事件导入，但会有意跳过 user-info 和 avatar enrichment，无法修复缺失的 user/avatar 数据。
- 手动导入、DLQ 重放和数据修复都属于变更操作。默认只做分析并制定恢复计划；执行前必须明确 manifest/message/row 范围，评估部分写入/幂等性，设置停止条件，并单独取得授权。

## 告警

Gateway Feishu 投递采用异步方式，超时为五秒；同一进程内按 key 抑制五分钟，并使用有界内存队列。投递失败不会改变事件事务或 MQ ACK/NACK。

主要告警包括：

- 消息发送到 DLQ；
- RabbitMQ 断开/重连边界；
- ACK/NACK 失败和 consumer panic；
- user enrichment 或 avatar-job enqueue 失败；
- avatar/manual 子系统启动失败；
- 最终 manual-import 失败；
- 进程异常退出。

没有告警不能证明系统健康，仍需日志和运行时/数据证据。

## 诊断路径

### MQ 积压或没有消费

检查两个 systemd 服务及其实际版本、RabbitMQ consumer 启动/重连证据、consumer count、ready/unacked count、queue binding 和当前 run 历史。某个竞争消费实例没有流量，不能证明链路已停止。

### 消息进入 DLQ

关联 eventId、准确的 manifestPath、part 名称和 failure classification。决定恢复操作前，应检查 manifest completion/identity、TOS 访问、失败的 part 和已经提交到 PostgreSQL 的 parts。不得仅凭聚合症状重放整个 DLQ。

### 数据库只有部分事件

将 manifest part order/object key 与数据库 `object_key` 对比；确定第一个失败的 part，并核验每个已提交 part 在两个 schema 中的状态。事件重放可能具有幂等性，但 user/avatar 的影响具有不同恢复语义。

### 事件存在但用户或头像缺失

检查 import summary、`tiktok.user_info` 和 `tiktok.avatar_mirror_job`。这些路径可能已经 ACK。手动 manifest 导入会跳过它们，因此应制定独立的补偿方案，不能盲目重放事件导入。

### Action 绿色但业务异常

检查两个实例的实际 binary 版本和启动日志、TOS 读取、事件 INSERT、DLQ、user/avatar 子系统及真实 manifest 结果。Readiness 不覆盖完整数据路径。

### Readiness 失败

等待 deployment workflow 完成，并确认是否恢复了 `.previous`、旧进程是否真正重启。自动恢复进行中时，不得同时触发操作员回滚。随后将服务恢复与已处理数据造成的后果分别处理。
