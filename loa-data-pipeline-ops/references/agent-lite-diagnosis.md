# Agent Lite 诊断

代码仓库：[Lighthunter-PTE-ltd/loa_agent_lite](https://github.com/Lighthunter-PTE-ltd/loa_agent_lite)。Agent Lite 包含 Worker、Realtime Gateway、Gateway B、Agent runtime 和 Fan Radar。使用本地 clone 时先核验 origin；静态代码、历史运行快照和当前生产状态必须分开表述。

## 生产只读日志访问

Agent Lite 核心服务当前已知日志入口是 journald。当前请求明确要求生产诊断时，先按 [access-channel.md](access-channel.md) 将 `agent-lite-prod-a|agent-lite-prod-b` 绑定到当前使用者已获批的 SSH、BytePlus 会话或专用只读工具；Skill 不要求固定 SSH alias。不得索取 SSH 密钥、读取 `.env` 值、绕过 host key 或跳板机，也不得执行服务控制、文件写入、部署或数据存储写操作。

常用只读命令：

```bash
systemctl status loa-agent-worker.service --no-pager
systemctl status loa-agent-gateway.service --no-pager
systemctl status loa-agent-gateway-b.service --no-pager
journalctl -u loa-agent-worker.service --since '<start>' --until '<end>' --no-pager
journalctl -u loa-agent-gateway.service --since '<start>' --until '<end>' --no-pager
journalctl -u loa-agent-gateway-b.service --since '<start>' --until '<end>' --no-pager
```

生产 A/B 的 OS hostname 相同。每项日志证据必须标注逻辑节点 `node=prod-a|prod-b`，不能只记录 hostname，也不要把某位使用者的 SSH alias 当成共享节点身份。输出前按 request ID、run ID、session ID、GUID、日期和时间窗在远端裁剪；不得读取或回传不受限 journal、原始用户消息、Agent audit payload、数据库内容或 `.env`。

## 生产访问通道

共享拓扑要求生产 A/B 经安全堡垒机或 BytePlus 受控会话访问，不把私网 IP 直连作为默认路径。每位使用者自行维护获批的 SSH host token、账号和身份；这些值不进入 Skill。SSH 场景可用 `ssh -G <当前使用者的-host-token>` 只读核验 `hostname`、`port`、`proxyjump`、`hostkeyalias`、`stricthostkeychecking` 和 `identitiesonly`，不要输出 `user` 或 `identityfile`。

首次 authenticity prompt 校验的是服务器 host key，不是客户端私钥。必须从可信控制台独立核验后再固定；host key 变化时停止并核验实例/轮换事实。`UNKNOWN port 65535` 可能只是 ProxyJump 前置失败后的包装错误。私网 IP 直连超时通常只说明当前网络没有该路由，不得据此误判目标 sshd。2026-08-28 曾由一位获批操作员验证安全堡垒机到 `10.0.1.218/219:22` 可达；其他使用者仍需独立核验自己的绑定。

## BytePlus TLS 日志采集

截至 2026-08-25，生产基础采集链路已经验证可覆盖实际安装的 Worker/Gateway units 写入 journald 的日志。Worker 只部署在 `prod-a`，所以 Worker 日志只出现在 A；Gateway 同时部署在 A/B，用户已确认 `MESSAGE:"[gateway] Fan Radar request"` 在两台节点的 TLS 数据中均可见。此前 Prod B 空窗口是没有触发该日志的业务流量，不是 collector、规则或采集范围故障。

测试实况：Region `ap-southeast-1`，私网 endpoint `https://tls-ap-southeast-1.ibytepluses.com`；Project/Topic/host group 均为 `oc-agent-test`，Topic ID `294f5549-286b-42b0-b335-9c52cdf25215`，规则 `oc-agent-test-application`。核验时 heartbeat normal、`HarvesterNum=1`、`RuleNum=1`、成功发送 29 条、失败与丢弃为 0；操作员确认空查询、环境查询和 Worker unit 查询均有结果。

生产实况：Region `ap-southeast-1`，私网 endpoint `https://tls-ap-southeast-1.ibytepluses.com`；Project/Topic `oc-agent-prod`，Topic ID `09508bca-ee7a-4584-a7ad-0322c30f9e7c`，2 个分区、7 天保留期。A/B 分别使用 host group `oc-agent-prod-a|b`、rule `oc-agent-prod-a|b-application` 和固定字段 `node=prod-a|prod-b`。两台 collector/exporter 均 active/enabled、`NRestarts=0`，配置解析目标均为 `0600 root:root`；A 上报 IP `10.0.1.218`，B 上报 IP `10.0.1.219`。

生产 A 已证明 Worker journal、JSONL、harvester/rule、成功发送和 TLS 查询链路。生产 A/B 又通过实际 Fan Radar 请求日志证明 Gateway journal → JSONL → LogCollector → TLS 链路可用。早期 B 的 JSONL 为 0、`HarvesterNum=0`、成功上传数为零，是当时没有匹配业务日志的时间点证据；有业务触发后，两台节点均能检索 Gateway 日志。

这项确认只证明“应用已经打印的日志能够被采集”。Agent Lite Gateway 没有覆盖所有路由的统一 access logger；`[gateway] Fan Radar request` 仅在 `/agent/v1/me/fan-radar*` 请求完成时产生。当前 Topic 不能替代 ALB access log，也不能用日志条数精确还原全部 A/B 流量。

拟定链路：

```text
loa-agent-* stdout/stderr
  -> journald
  -> loa-agent-lite-tls-export.service
  -> /var/log/loa-agent-lite/application.jsonl
  -> BytePlus LogCollector JSON mode
  -> Test 或 Prod TLS Topic
```

首期边界：

- 保留 journald；exporter 不修改应用 unit 输出，并匹配实际安装的 Worker、Gateway 和 Gateway B units。只采集应用已经写入 journald 的内容。
- JSONL 是 journald envelope；原应用输出位于 `MESSAGE`，服务名位于 `_SYSTEMD_UNIT`。
- Test/Prod 分 Topic 和 IAM；生产 A/B 分 host group/rule，并注入 `node=prod-a|prod-b`。
- 首期不回灌历史 journal，不采集 `.env`、数据库/MQ payload、Agent audit 表或原始用户消息文件。
- Agent Lite 日志可能包含用户/会话标识符和错误对象。发现凭据、Authorization header、完整用户消息或模型原始 payload 时，立即暂停规则并限制 Topic 权限。

### 日常验证顺序

四个层级分别得出结论：

1. **应用与 exporter：** 确认目标 unit 正常、目标 journal 在相关业务发生时有新记录、exporter active/enabled、JSONL 增长且逐行可解析。
2. **采集器运行：** `logcollectord.service` active/enabled，版本/Region/endpoint 正确且无异常重启。
3. **采集器上传：** heartbeat normal，对应 rule/harvester 已加载，成功请求/日志计数增加，失败与丢弃为零。
4. **TLS 可检索：** 正确 Topic/时间窗内空查询有结果，随后按 `environment`、`node`、`_SYSTEMD_UNIT` 过滤。

Worker 仅部署在 Prod A，因此 Worker 日志只对 A 验收。Gateway 部署在 A/B；两台已通过实际 Fan Radar 请求日志完成基础采集验证。后续空查询应先核对时间窗口内是否发生了会打印日志的业务，再检查目标 unit journal、JSONL 和采集器指标；不要把“没有业务日志”直接诊断为采集故障。

主机只读检查：

```bash
systemctl is-active loa-agent-lite-tls-export.service
systemctl is-enabled loa-agent-lite-tls-export.service
systemctl show loa-agent-lite-tls-export.service --property=ActiveState,SubState,NRestarts,ExecMainStartTimestamp --no-pager
stat -c '%a %U:%G %s %y %n' /var/log/loa-agent-lite/application.jsonl
tail -n 100 /var/log/loa-agent-lite/application.jsonl | jq -e 'has("MESSAGE") and has("_SYSTEMD_UNIT") and has("__CURSOR")' >/dev/null
tail -n 100 /var/log/loa-agent-lite/application.jsonl | jq -r '._SYSTEMD_UNIT // empty' | sort | uniq -c
systemctl is-active logcollectord.service
systemctl is-enabled logcollectord.service
/usr/local/logcollector/logcollector -v
stat -L -c '%a %U:%G %n' /usr/local/logcollector/etc/logcollector.yml
```

JSON 投影只应返回 unit 名和数量，不输出 `MESSAGE`。LogCollector 配置可能含 AK/SK；禁止输出 `/usr/local/logcollector/etc/logcollector.yml` 内容，只核验严格的 root-only 权限。该路径是符号链接时，链接自身显示的 `777` 没有安全意义，必须使用 `stat -L` 检查解析目标；`2.4.2` 安装器曾留下 `0644` 目标，测试节点已收紧为 `0600 root:root`，后续安装或升级必须重新核验。

TLS 查询先使用空查询，再按实际索引尝试：

```text
environment:test AND node:test
_SYSTEMD_UNIT:"loa-agent-worker.service"
environment:prod AND node:prod-a AND _SYSTEMD_UNIT:"loa-agent-worker.service"
environment:prod AND node:prod-a AND MESSAGE:"[gateway] Fan Radar request"
environment:prod AND node:prod-b AND MESSAGE:"[gateway] Fan Radar request"
MESSAGE:"Fan Radar materializer error"
MESSAGE:"provider health probe"
```

Fan Radar 请求日志可以验证两台 Gateway 的基础日志采集，但只覆盖该 API 自身；不能据此推断其他路由或全部 ALB 流量都有日志。

Exporter/collector heartbeat 不证明 Agent Lite 应用健康；TLS 检索命中也不证明 Worker、Gateway、模型、PostgreSQL、RabbitMQ 或 Fan Radar 数据路径健康。Fan Radar 数据缺失仍应从 [end-to-end-diagnosis.md](end-to-end-diagnosis.md) 定位首个失效边界。

## Agent Lite 关键日志边界

- Gateway `/health` 是浅存活检查，不验证数据库、Redis、MQ、模型、Worker 或 Fan Radar。
- Worker 没有独立 HTTP readiness。只有 systemd active 或 Worker 日志存在，不能证明 scheduler/materializer 正常。
- `Fan Radar materializer error`、`live recap scheduler error`、用户生命周期 retry、provider health 和模型 fallback 是不同故障面，不应合并为“Worker 异常”。
- `MESSAGE` 可能包含 GUID、session/run/request ID 和 token 哈希。查询结果交给 Codex 前，只返回定位所需字段与少量脱敏记录。
- `PRIORITY` 来自 journald/stdout-stderr，不保证与每个 `console.info|warn|error` 完全对应；告警阈值必须根据实际样本校准。

## 停止条件

以下情况停止推广或暂停采集规则：

- Region、Project、Topic、host group、节点固定字段与目标主机冲突；
- exporter 持续重启、JSONL 解析失败、cursor 异常或磁盘增长超出预算；
- LogCollector 对 Agent Lite CPU、内存、磁盘或 journal IO 产生明显影响；
- 规则误采其他服务/轮转文件，或出现未受控敏感数据；
- 生产 A/B 无法通过 `node` 可靠区分。

暂停采集不会删除已写入 TLS 的数据。若敏感数据已上传，应立即限制查询权限，并由 TLS 管理员按合规流程处理保留或删除。
