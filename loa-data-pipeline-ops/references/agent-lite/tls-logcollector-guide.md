# Agent Lite 日志接入 BytePlus TLS 指南

- **状态：** PROD AGENT JOURNAL COLLECTION VERIFIED（Worker：prod-a；Gateway：prod-a/prod-b）
- **最后更新：** 2026-08-25
- **适用组件：** `loa_agent_lite`
- **目标节点：** `lc-oc-test-lite`、`prod-a`、`prod-b`
- **文档性质：** 人工配置指南、安装资产、风险边界与验收基线

## 1. 结论

Agent Lite 可以复用 Crawler 已验证的“主机文件 → BytePlus LogCollector → TLS Topic”链路，但不能直接照抄 Crawler 的日志源和 multiline 规则。

Agent Lite 的 Worker/Gateway 当前通过 systemd 把 stdout/stderr 写入 journald，没有稳定的应用日志文件；日志格式也混合了普通文本、对象格式化输出和少量 JSON 字符串。首期方案因此是：

```text
loa-agent-* stdout/stderr
  -> journald（保留现有本地日志入口）
  -> loa-agent-lite-tls-export.service
  -> /var/log/loa-agent-lite/application.jsonl
  -> BytePlus LogCollector（JSON mode）
  -> environment-specific TLS Topic
```

Exporter 资产使用 `journalctl --output=json`，可以读取实际已安装的以下 unit：

- `loa-agent-worker.service`
- `loa-agent-gateway.service`
- `loa-agent-gateway-b.service`

它不修改 Agent Lite 业务代码，不改变现有 unit 的 `StandardOutput=journal`，也不读取 `.env`。截至 2026-08-25，生产环境已确认 Worker 日志可从 `prod-a` 进入 TLS，Gateway 日志可从 `prod-a` 和 `prod-b` 进入 TLS。Worker 只部署在 A，因此 Worker 日志只应出现在 A；Gateway 部署在 A/B，只有应用实际打印日志时才会进入该链路。当前基础配置不采集 ALB 日志，也不会为未埋点的 Gateway 路由生成通用 access log。

## 2. 已确认事实与待核验项

仓库、workflow 和 2026-08-22 运行时快照已经确认：

- 测试节点运行 Worker、主 Gateway 和 Gateway B；生产 A 运行 Worker + Gateway；生产 B 只运行 Gateway。
- 三个节点的核心服务均把 stdout/stderr 写入 journald。
- 生产 A/B 的 OS hostname 相同，不能只依赖 hostname 区分节点。
- Agent Lite 当前使用 `console.info`、`console.warn`、`console.error`，不是统一的应用级 JSON logger。
- 日志可能包含 GUID、session/run/request ID、token 哈希指纹、provider/model 名和错误对象；不应进入 Crawler 或 Gateway 的普通 Topic。

以下信息必须由操作员在每个目标 Region、主机和 TLS 控制台独立核验：

- ECS Region、目标 TLS Project/Topic 和 endpoint。
- 主机是否已安装 LogCollector、实际版本、配置文件权限和 heartbeat。
- `journalctl` 是否支持 `--cursor-file`；本方案要求 systemd 242 或更高版本。
- Exporter 对 CPU、磁盘和 journal IO 的影响，以及 JSONL 日增量和最大单行大小。
- TLS Topic 的 IAM、保留期、索引费用、masking 和告警负责人。
- 日志样本是否出现凭据、Authorization header、原始用户消息或超出预期的业务 payload。

生产和测试 Agent Lite TLS 资源均已确认位于 `ap-southeast-1`，当前使用私网 endpoint `https://tls-ap-southeast-1.ibytepluses.com`；必须保留 `https://`。新环境仍必须使用控制台给出的同 Region endpoint，不能把该值无条件复制到其他 Region。

### 2.1 测试节点运行快照（2026-08-24）

以下证据只表示 `lc-oc-test-lite` 在该时间点的采集状态，后续诊断仍应重新核验：

- TLS Region：`ap-southeast-1`；私网 endpoint：`https://tls-ap-southeast-1.ibytepluses.com`。
- Project：`oc-agent-test`；Topic：`oc-agent-test`；Topic ID：`294f5549-286b-42b0-b335-9c52cdf25215`。
- Host group：`oc-agent-test`；LogCollector 上报 IP：`172.31.47.34`；操作员确认 heartbeat 为 Normal。
- Rule：`oc-agent-test-application`；精确路径：`/var/log/loa-agent-lite/application.jsonl`；JSON、增量 `10 KiB`、采集时间点、hostname 字段、四个测试固定字段，未启用原始日志、解析失败原文上传、插件、全文索引、自动索引或统计。
- 键值索引字段为 `hostname`、`component`、`environment`、`node`、`log_type`、`_SYSTEMD_UNIT`、`_HOSTNAME`、`SYSLOG_IDENTIFIER`、`_PID`、`PRIORITY`、`__REALTIME_TIMESTAMP`、`__CURSOR`、`MESSAGE`；类型均为 `text`。
- `loa-agent-lite-tls-export.service` 已安装并为 `active/enabled`，`NRestarts=0`；JSONL 权限为 `640 root:root`，抽样逐行 JSON 校验通过并持续增长。
- LogCollector `2.4.2` 已安装，`logcollectord.service` 为 `active/enabled`、`NRestarts=0`；实际配置目标 `/usr/local/filebeat-7.12.0/etc/filebeat.yml` 已从安装后的 `0644` 收紧为 `0600 root:root`，入口 `/usr/local/logcollector/etc/logcollector.yml` 是指向它的符号链接。
- 规则下发后的主机指标为 `HeartbeatStatus=normal`、`HarvesterNum=1`、`RuleNum=1`、`SendSuccessfulReqs=2`、`SendSuccessfulLogCount=29`、`SendFailReqs=0`、`SendDropLogCount=0`，且未命中认证、endpoint 或解析错误信号。
- 操作员确认同一 Topic 最近 30 分钟的空查询、`environment:test AND node:test` 和 `_SYSTEMD_UNIT:"loa-agent-worker.service"` 均有结果。
- 验收时 Worker、主 Gateway、Gateway B 均保持 `active`。这些证据证明测试节点的 exporter、collector 上传和 TLS 可检索链路，不证明 Worker scheduler、Gateway 依赖、模型、PostgreSQL、RabbitMQ 或 Fan Radar 数据路径健康。

### 2.2 生产 A Worker/Gateway 日志采集快照（2026-08-25）

- TLS Region 为 `ap-southeast-1`；Project/Topic 均为 `oc-agent-prod`，Topic ID 为 `09508bca-ee7a-4584-a7ad-0322c30f9e7c`，2 个分区、保留 7 天。
- Host group 为 `oc-agent-prod-a`，ID `cd60696d-81a6-48f9-8ba7-5dabe93d188a`，上报 IP `10.0.1.218`，heartbeat 为 Normal。
- Rule 为 `oc-agent-prod-a-application`；精确路径、JSON 模式、增量 `10 KiB`、采集时间点、hostname、固定字段和 13 个键值索引均符合第 4、5 节基线；全文索引、预留字段索引、自动更新和统计均关闭。
- Exporter 与 LogCollector `2.4.2` 均为 active/enabled、`NRestarts=0`；LogCollector 配置解析目标为 `/usr/local/filebeat-7.12.0/etc/filebeat.yml`，权限为 `0600 root:root`。
- 采集器快照为 `HarvesterNum=1`、`RuleNum=1`、成功发送计数大于 0、失败和丢弃为 0；操作员已在 TLS 页面看到 `prod-a` Worker 日志，随后又确认 `prod-a` 的 `[gateway] Fan Radar request` 日志可检索。
- `2026-08-25 11:21 CST` 的源侧对比显示：Worker journal 最近 1 小时 648 条、24 小时 15,547 条，最新到 `11:21:39`；JSONL 为 5,526,677 bytes、10,852 行，末尾 5,000 行均来自 Worker。Gateway journal 最近 1 小时 0 条、24 小时 79 条，最后一条为 `2026-08-24 23:05:34`。
- 因此 `prod-a` 文件持续增长主要证明 Worker 有增量，不应推断 Gateway 或 ALB 访问日志也在持续写入。

### 2.3 生产 B Gateway 日志采集验证（2026-08-25）

- Host group 为 `oc-agent-prod-b`，ID `806ca2ed-29d9-4772-9aba-b64e7dd31903`，上报 IP `10.0.1.219`，heartbeat 为 Normal。
- Rule 为 `oc-agent-prod-b-application`，与 Prod A 使用相同采集与索引基线，仅固定字段 `node=prod-b`。
- Exporter 与 LogCollector `2.4.2` 均为 active/enabled、`NRestarts=0`；LogCollector 配置解析目标权限为 `0600 root:root`。
- 早期快照为 `RuleNum=1`、`HarvesterNum=0`、成功/失败/丢弃计数均为 0，JSONL 为 0 bytes；当时 Gateway 最近 1 小时没有新 journal。该快照只表示时间窗口内没有触发会打印日志的业务流量。
- 用户随后确认 `MESSAGE:"[gateway] Fan Radar request"` 可在 `prod-b` 的 TLS 数据中命中；同一日志在 `prod-a` 也可见。这证明 B 的 Gateway journal、exporter、JSONL、LogCollector、host group、rule 与 TLS 查询链路均正常。
- `prod-b` 只部署 Gateway，没有 Worker，因此 B 不会出现 Worker 日志；但只要 Gateway 业务路径实际调用 `console.*`，当前基础采集配置可以上传该日志。
- 两台 Gateway 均保持 active、监听 `0.0.0.0:18765`；快照时各有 31 个 established connections。该证据说明“连接存在”不等于应用向 journald 写访问日志。
- 当前结论是基础 Agent journald 采集配置没有问题。空时间窗口应先核对相关业务是否发生及应用是否会打印日志，不得直接归因于 collector。`[gateway] Fan Radar request` 只覆盖 Fan Radar 客户端 API，不能替代全路径 Gateway access log 或 ALB 日志。

## 3. 随附安装资产

本 Skill 的 [`assets/agent-lite-tls/`](../../assets/agent-lite-tls/) 提供三个可审计资产：

- `loa-agent-lite-tls-export.sh`：识别已安装 Agent Lite units，从当前 journal cursor 之后持续导出 JSONL。
- `loa-agent-lite-tls-export.service`：独立 systemd 服务，创建受限的 state/log 目录并保持 exporter 运行。
- `loa-agent-lite-tls-export.logrotate`：按天或达到 `100M` 轮转，保留 7 代并压缩。

Exporter 每 2 秒批量读取一次 journal，并在每批结束时通过 cursor file 持久化进度。异常掉电或 `SIGKILL` 仍可能重放当前小批次；TLS 应索引 `__CURSOR` 以便识别。日志轮转使用 `copytruncate`，上线后必须观察一次轮转边界的重复/遗漏风险。

首次启动只从当前 cursor 之后读取，不回灌历史 journald。需要历史日志时，继续使用范围严格的 `journalctl --since/--until` 人工协作流程，不应临时把 exporter 改成全量回放。

## 4. 推荐 TLS 资源与字段

建议将测试与生产分开，名称可按团队规范调整，但语义不要改变：

- Test host group：`loa-agent-lite-test`
- Prod Project/Topic：`oc-agent-prod`
- Prod A host group：`oc-agent-prod-a`
- Prod B host group：`oc-agent-prod-b`
- Test Topic：`loa-agent-lite-test-application`
- Test rule：`loa-agent-lite-test-application`
- Prod A rule：`oc-agent-prod-a-application`
- Prod B rule：`oc-agent-prod-b-application`

测试环境实际采用团队命名 `oc-agent-test` 作为 Project、Topic 和 host group，并使用 `oc-agent-test-application` 作为 rule；这是已验证的实际资源名。上面的名称继续作为新环境命名建议，不应据此重命名已接通资源。

生产资源已经按上述名称创建并验证：Project/Topic `oc-agent-prod`，Topic ID `09508bca-ee7a-4584-a7ad-0322c30f9e7c`，2 个分区、保留 7 天，Region `ap-southeast-1`；Prod A/B host group 与 rule 的实际 ID、状态见第 2 节。

三个规则使用同一精确路径：

```text
/var/log/loa-agent-lite/application.jsonl
```

Test 固定字段：

```text
component=agent-lite
environment=test
node=test
log_type=application
```

Prod A 固定字段：

```text
component=agent-lite
environment=prod
node=prod-a
log_type=application
```

Prod B 固定字段：

```text
component=agent-lite
environment=prod
node=prod-b
log_type=application
```

不要只使用 `_HOSTNAME` 区分生产 A/B。两台生产节点的 OS hostname 相同，必须通过不同 host group/rule 注入 `node=prod-a|prod-b`。

## 5. 人工实施步骤

### 5.0 生产 SSH 连接基线

本机生产别名应通过 `~/.ssh/config` 的 include 文件解析为：`lc-oc-prod-bastion` 访问公网堡垒机，`lc-oc-prod-lite-a|b` 使用 `ProxyJump lc-oc-prod-bastion` 访问两个私网节点。三个生产别名使用同一生产客户端身份，与测试身份不同；知识库不得记录身份文件路径。

2026-08-24 已为三个生产别名配置稳定 `HostKeyAlias` 和 `StrictHostKeyChecking yes`，并按别名固定 ED25519 host key。日常连接直接使用：

```bash
ssh lc-oc-prod-lite-a
ssh lc-oc-prod-lite-b
```

若出现 authenticity prompt、host identification changed、`UNKNOWN port 65535` 或连接超时：

1. 用 `ssh -G <alias>` 只核验 `hostname`、`proxyjump`、`hostkeyalias`、`stricthostkeychecking` 和 `identitiesonly`，不要输出 `identityfile`。
2. authenticity prompt 是服务器 host key 关口，不表示选错客户端生产私钥；必须经可信控制台核验指纹后再固定。
3. 不要设置 `ProxyJump=none`；这会让本机直接连接 `10.0.1.218/219` 并超时。
4. `UNKNOWN port 65535` 常是 ProxyJump 前置连接失败后的包装错误，不是目标 SSH 端口真的变为 65535。
5. host key 变化时立即停止，先核验实例是否重建或密钥是否轮换，不得删除旧记录后盲目接受。

### 5.1 只读预检

先在每台目标主机确认 systemd、实际 unit 和现有日志入口：

```bash
systemd --version | head -n 1
journalctl --help | grep -F -- '--cursor-file'
systemctl is-active loa-agent-worker.service 2>/dev/null || true
systemctl is-active loa-agent-gateway.service 2>/dev/null || true
systemctl is-active loa-agent-gateway-b.service 2>/dev/null || true
systemctl show loa-agent-worker.service loa-agent-gateway.service loa-agent-gateway-b.service \
  --property=Id,LoadState,ActiveState,SubState,StandardOutput,StandardError \
  --no-pager 2>/dev/null
journalctl --disk-usage
```

预期至少一个 Agent Lite unit 为 `loaded`，现有输出仍指向 journal。缺少 `--cursor-file` 时停止，不要用无状态 `journalctl -f` 替代，否则 exporter 重启后的重复范围不可控。

### 5.2 在测试节点安装 exporter

以下是主机状态变更。先取得对 `lc-oc-test-lite` 的明确授权，再将 `<skill-root>` 替换为当前 Skill 根目录：

```bash
sudo install -m 0755 \
  <skill-root>/assets/agent-lite-tls/loa-agent-lite-tls-export.sh \
  /usr/local/sbin/loa-agent-lite-tls-export
sudo install -m 0644 \
  <skill-root>/assets/agent-lite-tls/loa-agent-lite-tls-export.service \
  /etc/systemd/system/loa-agent-lite-tls-export.service
sudo install -m 0644 \
  <skill-root>/assets/agent-lite-tls/loa-agent-lite-tls-export.logrotate \
  /etc/logrotate.d/loa-agent-lite-tls-export
sudo systemd-analyze verify /etc/systemd/system/loa-agent-lite-tls-export.service
sudo logrotate --debug /etc/logrotate.d/loa-agent-lite-tls-export
sudo systemctl daemon-reload
sudo systemctl enable --now loa-agent-lite-tls-export.service
```

安装后只读检查：

```bash
systemctl is-active loa-agent-lite-tls-export.service
systemctl is-enabled loa-agent-lite-tls-export.service
systemctl show loa-agent-lite-tls-export.service \
  --property=User,Group,ActiveState,SubState,NRestarts,ExecMainStartTimestamp \
  --no-pager
stat -c '%a %U:%G %s %y %n' /var/log/loa-agent-lite/application.jsonl
namei -l /var/log/loa-agent-lite/application.jsonl
tail -n 100 /var/log/loa-agent-lite/application.jsonl \
  | jq -e 'has("MESSAGE") and has("_SYSTEMD_UNIT") and has("__CURSOR")' >/dev/null
tail -n 100 /var/log/loa-agent-lite/application.jsonl \
  | jq -r '._SYSTEMD_UNIT // empty' | sort | uniq -c
```

最后一条命令只输出 unit 名和数量，不输出日志正文。若文件暂时为空，先等待正常应用活动；不要为了验收制造真实用户请求或输出秘密。

### 5.3 安装 LogCollector 与创建 host group

1. 在 TLS 控制台确认 ECS 与 Project/Topic 位于同一 Region。
2. 使用控制台为该 Region 生成的官方流程安装 LogCollector。AK/SK 只由操作员在目标主机终端交互输入，不粘贴到聊天、文档、命令历史或工单；安装后立即 `unset`。
3. IP 类型 host group 必须在安装时显式指定该主机私网 IP；生产 A/B 分别为 `10.0.1.218`、`10.0.1.219`，不要同时添加 `--label`。
4. 只核验 `/usr/local/logcollector/etc/logcollector.yml` 的解析目标权限为严格 root-only（例如 `600 root:root`），禁止输出配置内容或凭据。
5. 创建 host group 时使用 LogCollector 实际上报的 IP；不要根据公网/私网拓扑猜测。
6. 等待 heartbeat 为 normal 后再创建采集规则。

生产安装采用的无凭据模板如下；`<HOST_PRIVATE_IP>` 只能替换为当前目标主机的私网 IP：

```bash
read -r -p 'BytePlus AK: ' TLS_SECRET_ID
read -r -s -p 'BytePlus SK: ' TLS_SECRET_KEY
printf '\n'
wget https://logcollector-ap-southeast-1.tos-ap-southeast-1.ivolces.com/logcollector.sh \
  -O /tmp/logcollector.sh
chmod 700 /tmp/logcollector.sh
sudo /tmp/logcollector.sh install \
  --region ap-southeast-1 \
  --endpoint https://tls-ap-southeast-1.ibytepluses.com \
  --secret_id "$TLS_SECRET_ID" \
  --secret_key "$TLS_SECRET_KEY" \
  --ip <HOST_PRIVATE_IP>
unset TLS_SECRET_ID TLS_SECRET_KEY
```

不要把替换后的完整安装命令或终端回显复制到知识库。

只读检查：

```bash
systemctl is-active logcollectord.service
systemctl is-enabled logcollectord.service
systemctl show logcollectord.service \
  --property=User,Group,ActiveState,SubState,NRestarts,ExecMainStartTimestamp \
  --no-pager
/usr/local/logcollector/logcollector -v
stat -L -c '%a %U:%G %n' /usr/local/logcollector/etc/logcollector.yml
```

### 5.4 创建 JSON 采集规则

为对应 host group 创建规则：

- Collection path：`/var/log/loa-agent-lite/application.jsonl`
- Collection mode：JSON
- Time：首期使用采集时间；保留 `__REALTIME_TIMESTAMP`，验证微秒 epoch 的解析方案后再决定是否覆盖采集时间
- Policy：增量采集（`TailFiles=true`）
- Initial tail：`10 KiB`
- Hostname field：启用
- Fixed fields：使用第 4 节对应环境/节点字段
- Raw duplicate upload：关闭

只匹配当前 `.jsonl`，不要匹配 `.1` 或 `.gz`。JSONL 每行是 journald envelope，原始应用输出位于 `MESSAGE`；`_SYSTEMD_UNIT` 是服务维度，`PRIORITY` 是 journal priority。不要把 `MESSAGE` 假定为内嵌 JSON，也不要配置一个会因普通文本而持续失败的二次 JSON parser。

建议先为以下字段建立 key-value 索引：

```text
component environment node log_type
_SYSTEMD_UNIT _HOSTNAME SYSLOG_IDENTIFIER _PID PRIORITY
__REALTIME_TIMESTAMP __CURSOR MESSAGE
```

只有完成日志样本安全评审后，才为 `MESSAGE` 启用全文索引或广泛统计。生产 Topic 应使用最小查询权限和尽可能短、满足故障回溯要求的保留期。

### 5.5 生产推广结果与重建顺序

截至 2026-08-25，Prod A/B 均已完成 exporter、LogCollector、独立 host group 和独立 rule 配置。Worker 日志已在 Prod A 验证；`[gateway] Fan Radar request` 已在 Prod A/B 验证，因此两台节点的基础 Agent journald 采集链路均已接通。

后续重建或新增节点仍按以下顺序逐台执行，并逐台取得授权：

1. 安装 exporter，确认目标 unit、JSONL 权限和正常增量。
2. 安装 LogCollector，显式指定私网 IP，收紧配置解析目标权限。
3. 绑定该节点独立 host group，创建带正确 `node` 固定字段的独立 rule。
4. 对目标 unit 依次验证 journal、JSONL、harvester/发送计数和 TLS 查询；Worker 只在 A 验证，Gateway 在 A/B 分别验证。验证日志必须由正常业务自然产生，不通过重启或回灌制造证据。

不要把测试、生产 A、生产 B 绑定到同一 host group，也不要复用错误的 `node` 字段。

## 6. 验收顺序

四个层级必须分开验收：

1. **应用与 exporter：** 在部署 Worker 的节点确认 Worker unit 正常；Worker journal 有目标时间窗记录；exporter active/enabled；JSONL 文件增长且每行可解析。
2. **采集器运行：** `logcollectord.service` active/enabled，版本和 endpoint 符合目标 Region，未异常重启。
3. **采集器上传：** heartbeat normal，对应 rule/harvester 已加载，成功请求/日志计数增长，失败和丢弃为零。
4. **TLS 可检索：** 正确 Topic/时间窗内空查询有结果，并可按 `environment`、`node`、`_SYSTEMD_UNIT` 分别查询。

查询示例（以 Topic 当前索引语法为准）：

```text
environment:prod AND node:prod-a AND _SYSTEMD_UNIT:"loa-agent-worker.service"
environment:prod AND node:prod-a AND MESSAGE:"[gateway] Fan Radar request"
environment:prod AND node:prod-b AND MESSAGE:"[gateway] Fan Radar request"
MESSAGE:"Fan Radar materializer error"
MESSAGE:"provider health probe"
PRIORITY:3
```

Fan Radar 请求日志可用于验证 A/B Gateway 的基础日志采集链路，但仅覆盖 `/agent/v1/me/fan-radar*`；不能用它统计全部 Gateway 或 ALB 流量。

先用空查询证明 Topic 和时间窗有数据，再逐步增加过滤条件。Exporter/collector heartbeat 正常不证明 Agent Lite 应用健康；TLS 有日志也不证明 Worker、Gateway、模型、PostgreSQL、RabbitMQ 或 Fan Radar 数据路径正常。

Worker 仅部署在 Prod A，所以 Worker 日志只在 A 验证。Gateway 部署在 A/B，并已通过实际 Fan Radar 请求日志完成两台的基础链路验证。如果查询窗口为空，先确认窗口内是否调用了会打印日志的业务路径，再检查目标 unit journal、JSONL、harvester/cursor 和 TLS；业务无流量或正常路径没有日志埋点时，空查询不能诊断为采集故障。

## 7. 隐私、告警与 Codex 查询边界

- Test 与 Prod 使用不同 Topic 和 IAM；生产 Topic 不授予普通测试人员或默认自动化身份。
- 首期不采集 `.env`、部署目录、Runtime status JSON、数据库内容、MQ payload、Agent audit 表或原始用户消息文件。
- `MESSAGE` 可能包含 GUID、session/run/request ID、token 哈希和错误对象。分享给 Codex 前必须限定时间、node、unit 和关联键，并投影最少字段。
- 若发现 Authorization header、凭据、完整用户消息或模型原始 payload，立即暂停对应规则并限制 Topic 权限；停采不会删除已上传数据。
- 首批告警可覆盖 exporter/collector heartbeat、持续上传失败/丢弃、Worker materializer error、Gateway 5xx 和 provider health failure；“一段时间无应用日志”不能单独判定服务宕机。
- `PRIORITY` 来源于 journald/stdout-stderr，不保证与每个 `console.info|warn|error` 完全等价；告警上线前用实际样本校准。

## 8. 停止与回退条件

遇到以下任一情况立即停止推广或暂停规则：

- Region、Project、Topic、host group 或 `node` 固定字段与目标主机不一致。
- Exporter 持续重启、JSONL 无法逐行解析、cursor 异常或磁盘增长超出预算。
- LogCollector 明显影响 Agent Lite CPU、内存、磁盘或 journal IO。
- 失败/丢弃计数持续增长，或规则误采其他服务/轮转文件。
- 日志出现未受控凭据、Authorization header、原始用户消息或完整业务 payload。
- 生产 A/B 无法可靠按 `node` 区分。

回退时先解绑/暂停 TLS 采集规则，再在获得目标主机授权后停止 `loa-agent-lite-tls-export.service`。这不会更改 Agent Lite 原有 journald 输出。暂停/删除规则不会删除已写入 TLS 的日志；敏感数据已进入 Topic 时，必须由 TLS 管理员按合规流程限制权限并处理保留/删除。

## 9. 参考资料

- [LogCollector collection rule management](https://docs.byteplus.com/en/docs/tls/logcollector_collection_rule_management)
- [Host group overview](https://docs.byteplus.com/en/docs/tls/host_group_overview)
- [LogCollector plug-ins overview](https://docs.byteplus.com/en/docs/tls/plug-ins_Overview)
- [Troubleshoot abnormal host log collection](https://docs.byteplus.com/en/docs/tls/How-to-troubleshoot-abnormal-log-collection-on-the-host-machine)
- [journalctl cursor and JSON output](https://www.freedesktop.org/software/systemd/man/255/journalctl.html)
