# Agent Lite 运行时只读快照（2026-08-22）

查询窗口：2026-08-22 22:52–22:58 CST。

本文记录一次经用户明确授权的只读 SSH 探查。结论是时间点快照，不应在后续发布、重启或故障后继续当作当前状态。

## 1. 查询边界

- 目标：`lc-oc-test-lite`、`lc-oc-prod-lite-a`、`lc-oc-prod-lite-b`；生产连接经 `lc-oc-prod-bastion`。
- 只使用非交互 SSH 和 `hostname`、`date`、`uname`、`systemctl show/list-*`、`ss`、`stat`、`journalctl --disk-usage`、`systemd-analyze cat-config`、`find`、`sha256sum` 等读取命令。
- 没有使用 `sudo`、文件重定向、编辑、服务控制、包管理、HTTP 应用探针或数据存储查询。
- 没有读取 `.env` 值、密钥、业务日志正文、数据库内容或 MQ 消息；只读取了 `.env` 的权限、owner、mtime 和 size 元数据。
- 客户端将 `UserKnownHostsFile` 指向 `/dev/null`，没有写入本机 `known_hosts`。SSH 登录本身仍可能由远端 `sshd` 形成认证审计日志，这是客户端无法消除的系统副作用。

## 2. 主机和服务状态

三个应用节点均为 `Linux 6.8.0-55-generic x86_64`。

### 测试节点

- SSH 别名：`lc-oc-test-lite`
- OS hostname：`loa-agent-lite`
- `loa-agent-worker`：`enabled`、`active/running`；快照 PID `3548687`；启动时间 `2026-08-21 14:14:17 CST`
- `loa-agent-gateway`：`enabled`、`active/running`；快照 PID `3548692`；启动时间 `2026-08-21 14:14:18 CST`
- `loa-agent-gateway-b`：`enabled`、`active/running`；快照 PID `3548691`；启动时间 `2026-08-21 14:14:17 CST`

### 生产 A

- SSH 别名：`lc-oc-prod-lite-a`
- 私网 IP：`10.0.1.218`
- OS hostname：`prod-loa-agent-lite`
- `loa-agent-worker`：`enabled`、`active/running`；快照 PID `285482`；启动时间 `2026-08-21 10:56:35 CST`
- `loa-agent-gateway`：`enabled`、`active/running`；快照 PID `285479`；启动时间 `2026-08-21 10:56:35 CST`

### 生产 B

- SSH 别名：`lc-oc-prod-lite-b`
- 私网 IP：`10.0.1.219`
- OS hostname：`prod-loa-agent-lite`
- `loa-agent-gateway`：`enabled`、`active/running`；快照 PID `271538`；启动时间 `2026-08-21 10:57:25 CST`

生产 A/B 的 OS hostname 相同。诊断、发布和故障记录必须同时标注 SSH 别名或私网 IP，不能只依据 `hostname` 区分节点。PID 是易变信息，只用于关联本次快照。

## 3. 实际代码与回滚基线

运行目录不包含 Git metadata 或 release manifest，无法直接读取 commit。此次使用受控文件集合计算内容摘要，再与本地 Git 对象比较：只覆盖 release 中的源码、文档和根配置文件，排除 `.env`、`node_modules`、`.deploy-backups`、dashboard 构建产物及 macOS 元数据；不输出文件正文。

- 测试当前内容精确匹配 `d2fcbf50ea970d6e778a6b8cdab4ec8997f95b81`，即查询时的 `origin/main`。
- 生产 A/B 当前内容彼此一致；排除 macOS 元数据后，均精确匹配 `47405c886270ce814836698d0a2688b9ed9d81af`，即查询时的 `origin/prod`。
- 测试唯一自动备份 `20260821141417-before-auto-prerelease` 也匹配 `d2fcbf50...`。该备份与当前代码相同，不能提供代码版本降级。
- 生产 A/B 的唯一自动备份分别为 `20260821105635-before-auto-prerelease` 和 `20260821105724-before-auto-prerelease`；二者都匹配 `57b6616bccc80a641c8e2b160e999f03b4c0b3a0`。
- 生产 A/B 当前源码目录各有 405 个 `._*` / `.DS_Store` macOS 元数据文件。排除这些文件后没有源码漂移。标准 GitHub Linux runner 不应生成这些文件，因此当前制品至少曾经过 macOS 文件系统或非标准打包/复制环节；仅凭本次快照不能确定具体部署入口。用户随后说明该版本由其同事部署，用户本人不清楚实际部署方法，因此需要向实际部署人核验，不能继续从现象推断。

这组证据证明查询时的服务器内容版本，但不证明对应版本通过哪一次 workflow 或人工命令部署。未来发布应在运行目录写入不含秘密的 commit/release manifest，避免依赖昂贵的全树摘要反推版本。

## 4. Bun 与 systemd 运行约束

- 所有核心服务的绝对执行文件都是 `/root/.bun/bin/bun`；交互式 SSH 的默认 `PATH` 不包含 Bun，运维命令不能直接假设 `bun` 可用。
- 测试实际 Bun 为 `1.3.14`；生产 A/B 为 `1.3.13`。仓库 `packageManager` 和 workflow 固定版本均为 `1.3.13`，因此测试存在运行时版本漂移。用户说明测试环境也由同事部署，本人不清楚该差异是否有意；需向实际部署人核验，不能将其直接定性为升级或错误。
- 所有服务工作目录均为 `/opt/light_hunter/loa_agent_lite`，并通过 systemd `EnvironmentFiles` 读取 `/opt/light_hunter/loa_agent_lite/.env`。
- unit 未设置 `User` / `Group`，因此系统服务按默认 root 身份运行。
- `Restart=always`，`RestartSec=3s`，`TimeoutStopSec=90s`，`KillMode=control-group`，`KillSignal=SIGTERM`，必要时允许 `SIGKILL`。
- unit 未设置 systemd `MemoryMax` 或 CPU quota。测试 `LimitNOFILE=524288`；生产为 `1048576`。
- 测试 `gateway-b` 通过 `/usr/bin/env REALTIME_PORT=18766 REALTIME_RUNTIME_STATUS_PATH=/run/loa-agent-gateway-b/status.json` 启动，与主 Gateway 分离端口和 drain status 文件。
- unit 位于 `/etc/systemd/system/loa-agent-*.service`，owner 为 `root:root`、mode `0644`；`.env` 为 `root:root`、mode `0600`。

上述 systemd 事实补足了仓库没有提交核心 unit 的缺口，但不证明 Worker 能优雅停止：静态代码仍没有看到直接入口把 `SIGTERM`/`SIGINT` 连接到 `startWorker()` 返回的 stop handle。

## 5. 监听与日志

- 测试主 Gateway 监听 `0.0.0.0:18765`，Gateway B 监听 `0.0.0.0:18766`。
- 生产 A/B Gateway 均监听 `0.0.0.0:18765`。
- 这证明实际配置覆盖了代码默认的 `127.0.0.1`。用户随后确认生产 A/B 前方配置了统一的 BytePlus ALB `prod-public-alb`，私网 IP `10.0.0.76`、公网 IP `101.47.23.252`，对外监听 `HTTPS:443`、后端端口 `18765`，A/B 权重均为 `100`，调度算法为加权轮询 `WRR`，未开启会话保持。ALB 配置没有明确标注后端协议；仓库和运行时只证明 `18765` 上的 Gateway 提供 HTTP 服务。用户最终在 ALB 后端服务器组页签确认健康检查为“未配置”；此前看到的 `/actuator/health` 不是该服务器组的生效检查。因此当前 ALB 不会基于 Agent Lite 的应用 health 自动识别和摘除故障节点，同一用户请求也可能跨 Gateway，正确性依赖应用层共享状态与锁。
- 核心服务 `StandardOutput=journal`，`StandardError=inherit`；当前可按 journald 作为首要日志入口。
- 查询时 journal 占用：测试约 `2.1 GiB`、生产 A `478.8 MiB`、生产 B `110.5 MiB`。
- `systemd-analyze cat-config --tldr systemd/journald.conf` 没有返回显式的容量或保留时长覆盖项，因此不能声明固定保留天数；目前应按系统默认 journald 策略理解。

## 6. 本次快照没有证明的事项

- 没有调用 Gateway `/health`，也没有读取业务日志，因此只证明 systemd 进程状态和监听 socket，不证明请求成功率。
- 没有核验 Worker scheduler、PostgreSQL、Redis、RabbitMQ、TOS、LOA API、message-service、Mem0 或模型 provider 的可用性。
- 没有读取 `.env`，所以没有确认表前缀、ODS schema、feature flag、admin token、告警 webhook 或依赖地址。
- 已由用户确认生产 A/B 前方是 `prod-public-alb`（私网 `10.0.0.76`、公网 `101.47.23.252`），对外监听 `HTTPS:443`、后端端口 `18765`，A/B 权重均为 `100`，调度算法为加权轮询 `WRR`，未开启会话保持；ALB 后端协议未明确标注，后端服务器组未配置健康检查，且没有核验域名/路由、BytePlus 安全组、主机防火墙或故障节点人工摘除流程。
- 没有核验集中日志平台、告警送达闭环、自然直播端到端数据路径或历史故障恢复。
