# Data Gateway 接管知识底稿

更新日期：2026-08-24

本文整理 `loa-data-gateway` 的完整工程职责、数据契约、部署方式、失败语义和接管缺口。它是静态代码与仓库文档核验后的知识底稿，不等于线上状态已经验收，也不是改造方案。

## 1. 资料与当前代码基线

主要依据：

1. `loa-data-gateway` 当前 `main` 代码。
2. 仓库 [README](https://github.com/Lighthunter-PTE-ltd/loa-data-gateway/blob/main/README.md)。
3. GitHub Actions workflow 和 `.github/scripts/deploy-ecs.sh`。
4. 单元测试、依赖替身测试和本地 HTTP 集成测试。

2026-08-19 当前远端状态：

- `origin/main@f583e90a1e7428fa78737d2719a4c3371eea9da6`
- `origin/test@2651d7a430798b690df6c19333c2245e1bf6e7cf`
- `origin/dev@3875e8eb57eb8a1fa7f7f8dd81481c77d0eeba35`
- 三个分支 commit 不同，但当前 Git tree 完全一致，都是 `e72add41280ae377cf867151b2e7462835cfde92`。
- 本地仓库是干净的 `main`。

正式代码晋级顺序已确认为 `dev -> test -> main`。`dev` 本身不触发部署；push/合并到 `test` 或 `main` 会自动部署对应服务。用户已经人工确认和验证“合并到 `main` 后由 GitHub Actions 完成生产部署”这条路径。先部署 `test` 的目的，是在新版实例启动失败或宕机时保留旧版 `main` 实例继续消费，为终止晋级和回滚 `test` 争取时间。

这不是数据语义隔离机制。`test` 和 `main` 会竞争真实生产消息，并共享 TOS 和 PostgreSQL；只要新旧版本对同一消息的处理结果不同，就可能依据消息被哪个实例取得而产生不同结果，即使两个进程都没有宕机。后续常规修改默认保持共享数据链路语义向后兼容；涉及 MQ 契约、manifest/part 契约、消息过滤、ACK/NACK、重试/DLQ、幂等、事件映射、双 schema 写入或破坏性数据库结构变更时，必须先单独制定兼容和迁移方案，不能仅依赖 `dev -> test -> main` 降低风险。

## 2. 完整工程职责

Data Gateway 包含六类能力，全部属于接管范围：

1. 消费 Crawler 发布的 Legacy `live.ended` RabbitMQ 消息。
2. 从 TOS 读取并校验 manifest 和全部 part，向 PostgreSQL 导入直播事件。
3. 从事件中提取、合并并 upsert TikTok 用户快照。
4. 持久化头像镜像任务，异步下载头像、转换 JPEG、上传 TOS 并回写用户表。
5. 提供只监听回环地址的手工 manifest 重放接口。
6. 提供结构化普通日志、完整 MQ 事件日志、飞书告警、版本查询和自动部署/回滚。

面向主数据链路的流程：

```text
Crawler Legacy live.ended
  -> RabbitMQ durable queue
  -> 2 个进程内 MQ worker
  -> TOS manifest/parts 校验与读取
  -> 每个 part 同一事务写入两个事件 schema
  -> user_info 补充
  -> avatar_mirror_job 持久任务
  -> 4 个头像 worker 下载/转换/上传并回写 loa_avatar_url
```

另有独立恢复路径：

```text
回环 HTTP POST manifestPath
  -> 单个内存异步任务
  -> 独立单连接 PostgreSQL pool
  -> 复用 TOS 和事件导入逻辑
  -> 跳过 user_info 与头像补充
```

## 3. 启动顺序与依赖

进程入口为 `cmd/loa-data-gateway/main.go`，启动顺序大致为：

1. 读取并校验配置。
2. 打开独立 MQ 原始事件日志。
3. 创建 PostgreSQL 主连接池并执行 Ping。
4. 验证两个事件目标表存在且当前账号具备 SELECT/INSERT 权限。
5. 检查 `tiktok.user_info`；失败只告警，不阻止事件消费。
6. 创建头像专用连接池并验证 `user_info` 和 `avatar_mirror_job`；失败只告警，不阻止事件消费。
7. 创建 TOS client。此时只创建客户端，没有实际执行 GetObject/PutObject 探活。
8. 尝试启动手工导入 HTTP 子系统；失败告警，MQ 主链路仍可继续。
9. 连接 RabbitMQ、声明拓扑并启动 consumer。

事件目标 PostgreSQL 不可用会阻止服务启动；用户补充、头像和手工导入属于可降级子系统。

## 4. RabbitMQ 拓扑与消息处理

固定拓扑：

- topic exchange：`openclaw_skill_topic_exchange`
- binding：`user.pk.invitation.response.#`
- durable queue：`loa_data_gateway_live_ended`
- durable DLQ：`loa_data_gateway_live_ended_dlq`
- worker：2
- prefetch：2

启动时服务会幂等声明 exchange、queue 和 DLQ，移除历史 `crawler.event.monitor.#` binding，再绑定 Legacy routing key。

消息 body 先完整写入独立结构化事件日志，再交给 worker。处理规则：

- JSON 无法解析、缺少关键字段或归档合同不匹配：永久失败，NACK 且不重新入队，进入 DLQ。
- `eventType` 不是 `live.ended`：ACK 并忽略。
- TOS 读取、PostgreSQL 写入和未完成 manifest 等暂时错误：进程内最多尝试 5 次，指数退避；耗尽后仍进入 DLQ。
- 服务关闭打断重试或处理：NACK 并重新入队。
- ACK/NACK 失败或 consumer panic：告警并重建 RabbitMQ 消费连接；panic 对应消息不会被当前 worker确认。

需要特别注意：代码把“暂时错误”用于决定是否在本次消费中重试，但耗尽重试后不会长期 requeue，而是进入 DLQ。因此 DLQ 是正式恢复流程的一部分，不能只作为异常垃圾箱。

## 5. TOS manifest 与 part 合同

服务固定读取 Crawler 的生产归档 bucket，最大单对象默认 128 MiB。

导入前会校验：

- MQ 必须包含 `eventId`、`eventType`、GUID、roomId、sessionId 和 manifestPath。
- manifestPath 必须是相对 object key，不能包含父目录穿越。
- manifest schema、archive type、bucket、object key 必须符合约定。
- manifest 的 GUID、roomId、sessionId 必须与 MQ 一致。
- manifest 必须 `completed=true`。
- `uploaded_parts` 必须等于 `part_files` 数量。
- part filename 不能包含目录穿越。
- 每个 part 的 bucket、object key、GUID、roomId、sessionId、事件数和内部身份必须与 manifest 一致。
- 最终解码事件总数必须等于 manifest 的 `total_events`。

每个 part 读取、映射并独立提交。若 part 1、2 已成功而 part 3 失败，前两部分不会回滚；后续重放依赖事件 ID 的 `ON CONFLICT DO NOTHING` 实现幂等。

总事件数校验发生在所有 part 已写入之后。如果总数不匹配，消息会进入 DLQ，但之前已经提交的事件仍保留。故障定位时不能把“消息在 DLQ”理解为“数据库一条都没写”。

## 6. PostgreSQL 写入语义

每个 part 在一个事务内写入：

- `prod_liveonair_tiktok.ods_tiktok_live_event_detail`
- `test_liveonair_tiktok.ods_tiktok_live_event_detail`

对同一 part 而言，两个 schema 原子提交。事件以 `id/turn_id` 去重，冲突时跳过。应用不会自动创建或修改正式事件表；目标表和唯一约束必须预先存在。

需要区分三种一致性范围：

- 一个 part 内两个 schema：同一事务。
- 同一 manifest 的多个 part：逐 part 提交，不是一个总事务。
- 事件、用户信息、头像：相互隔离，事件成功优先。

仓库提供两份迁移：

- `001_event_id_primary_key.sql`：审计并为事件表 `id` 建立主键；脚本使用未限定 schema，执行时必须明确 search_path/目标 schema。
- `002_avatar_mirror_jobs.sql`：创建 `tiktok.avatar_mirror_job` 和领取索引。

迁移不会随应用启动或部署自动执行，需要独立审批和操作记录。

## 7. 用户信息与头像

MQ 导入完成全部事件后，从 SDK payload 或兼容 `from_user` 中提取 TikTok 用户。按 `source_timestamp` 合并快照，保留较新非空字段，然后在独立 5 秒预算内 upsert `tiktok.user_info`。

用户写入失败、超时或身份冲突：

- 会记录导入摘要并发送告警；
- 不回滚事件；
- 不改变 MQ ACK；
- 当前没有单独的 user_info 重放任务，手工 manifest 导入也会主动跳过用户补充。

用户行仍缺少 `loa_avatar_url` 时，在独立 1 秒预算内写入 `tiktok.avatar_mirror_job`。入队失败同样不会改变事件 ACK。

头像子系统：

- 默认 4 个 worker，使用独立 PostgreSQL pool。
- 任务通过数据库 lease 和 `FOR UPDATE SKIP LOCKED` 领取，进程重启后仍保留。
- 单次处理默认最多 10 秒；失败持续指数退避，代码中没有最大尝试次数。
- 仅允许 HTTPS、公网 IP 和 443 端口，限制重定向、下载大小及解码像素，降低 SSRF 和图片炸弹风险。
- JPEG/PNG/GIF/WebP 统一转成 JPEG。
- 目标 key 为 `tiktok/avatar/<escaped-username>/default.jpeg`，禁止覆盖已有对象。
- 成功后删除任务并仅在 `loa_avatar_url IS NULL` 时更新用户表。

## 8. 手工 manifest 导入

接口：

```text
POST /internal/v1/manifest-imports
```

它必须监听回环地址，没有应用层鉴权。主要行为：

- 只接收一个 `manifestPath`，立即返回 `202 Accepted`。
- 同时最多一个任务；忙时返回 `409 Conflict`。
- 没有任务 ID，也没有状态查询接口，结果只在普通日志和飞书告警中体现。
- 任务仅存在内存，进程重启或 SIGTERM 会取消；恢复后需要人工重新提交。
- 暂时失败采用与 MQ 相同次数和退避策略。
- 使用独立、最大连接数为 1 的 PostgreSQL pool。
- 复用事件幂等导入，但主动跳过 user_info 和头像，避免旧归档覆盖新快照。
- 不发布 RabbitMQ 消息。

手工重放应先确认 manifest 对应事件是否已部分入库、当前是否存在另一个手工任务，并在操作后通过日志和数据库证据验收。

## 9. 环境与部署

这里的 `test` 应理解为**测试分支代码的独立部署实例**，不能理解为一套隔离测试环境。

实际部署拓扑：

- BytePlus 云服务器名：`ECS-Uat-Test-Back`
- 公网 IP：无
- 私网 IP：`172.31.0.2`
- `main`：正式实例，端口 `8081`
- `test`：测试分支实例，端口 `8082`

两个端口在当前代码中分别是各实例的回环 HTTP 地址，绑定到 `127.0.0.1`，不会直接对宿主机外开放。

仓库当前部署两个独立 systemd 服务：

- `main` -> 正式服务 `loa-data-gateway.service`
- `test` -> 测试服务 `loa-data-gateway-test.service`

两者位于上述同一 ECS，但运行目录、二进制、环境文件、普通日志、事件日志、回滚文件和回环 HTTP 端口独立。它们竞争消费同一个 RabbitMQ durable queue，并且每个实例都会写入两个 PostgreSQL 事件 schema。这是当前已运行的既定架构，本接管任务不追究或重构。

GitHub Actions 在 push `main` 或 `test` 时自动部署，也支持从对应分支手工触发。workflow 使用 self-hosted runner，执行：

1. `go test ./...`
2. 构建静态 Linux AMD64 二进制并注入 branch/run number/commit。
3. 将二进制、环境文件、systemd unit 和 logrotate 配置上传到远端 staging。
4. 备份当前二进制和 `.env` 为 `.previous`。
5. 原子替换二进制和环境文件并重启服务。
6. 在 90 秒内从本次启动后的日志确认：正确 commit 的 `service starting`、手工 HTTP API启动、RabbitMQ consumer 启动。
7. readiness 失败时自动恢复上一份二进制和环境文件；首次部署无备份时停止失败服务。

systemd 对 SIGTERM 提供 130 秒停止窗口；RabbitMQ active work 默认最多 drain 2 分钟。自动回滚只覆盖部署 readiness 失败，不覆盖部署完成后才暴露的 TOS、数据库写入或业务数据错误。

需要区分两种回滚：

- 部署期自动恢复：本次 readiness 失败时，远端脚本恢复部署前备份的 `.previous` 二进制和 `.env`。
- 操作员版本回滚：从 GitHub Actions 页面或 GitHub API 触发已核验的已知良好提交/历史成功 run 重新部署。它依赖 GitHub 发布入口，不应写成服务器端旧二进制原位恢复；当前知识仍需补一份带 run ID、checkout SHA 和验收结果的 Gateway 实操记录。

当前部署 readiness 会验证 PostgreSQL 连接/事件表、手工 HTTP listener 和 RabbitMQ consumer，但不会实际验证 TOS GetObject、PostgreSQL 事件 INSERT、用户信息、头像处理、DLQ 或下游查询结果。

### 9.1 已确认的常规晋级边界

常规发布按以下顺序理解：

1. 在 `dev` 完成代码审查和可离线执行的测试。
2. 合并 `dev -> test`，由 workflow 部署 `loa-data-gateway-test.service`；旧版 `main` 服务保持运行。
3. 验证新版 `test` 的启动、持续运行以及允许观察的数据处理结果。若失败，停止晋级并恢复 `test`；不能假定旧版 `main` 会自动修复新版已经 ACK 或已经写入的数据。
4. 验证通过后合并 `test -> main`，由 workflow 部署正式服务，使两个竞争消费者最终回到同一版本。

该顺序主要防止单个新实例的进程故障造成整个消费链路同时不可用。它不能防止新旧版本竞争消费期间的数据处理差异，因此只适用于向后兼容、可幂等重放、不会因消费者版本不同而产生不同持久化结果的变更。若无法满足这些条件，应暂停常规发布并先讨论专门方案，例如契约兼容期、分阶段数据库迁移、消费路由隔离或受控停启；本文不预先选定方案。

合并到 `main` 后由 GitHub Actions 自动完成生产部署的路径已经人工确认和验证。当前证据不能扩张为完整 `dev -> test -> main` 晋级观测、操作员回滚或数据面验收均已实测；这些仍需分别保留证据。

## 10. 日志、版本与告警

版本检查：

```text
<binary> --version
```

普通日志和完整 MQ 事件日志分开保存，按天或超过 100 MiB 轮转，保留 14 个历史文件。事件日志包含完整 MQ body，可能包含用户和直播互动数据，接管时需要确认文件权限、备份范围和保留策略符合要求。

生产日志允许受控只读访问：当前请求明确要求生产诊断时，按 [生产访问通道与可移植绑定](../access-channel.md) 将 `gateway-shared` 绑定到当前使用者已获批的访问通道，再查询 `ECS-Uat-Test-Back` 的服务状态、版本和限定时间窗日志。服务器没有公网 IP，不得把私网地址当作任意环境可直连入口；不得索取、保存或代持密钥，不得读取 `.env`、完整 MQ payload，或执行服务、文件、配置和数据状态变更。

当前代码可确认的日志文件：

- `main` 普通日志：`/www/go-server/loa-data-gateway/logs/loa-data-gateway.log`
- `main` 完整 MQ 事件日志：`/var/log/loa-data-gateway/loa-data-gateway-event.log`
- `test` 普通日志：`/www/go-server/loa-data-gateway-test/logs/loa-data-gateway-test.log`
- `test` 完整 MQ 事件日志：`/var/log/loa-data-gateway-test/loa-data-gateway-event.log`

完整事件日志可能包含用户和直播互动数据。人工回传给 AI 前应按故障时间窗和 eventId/manifestPath 等关联字段裁剪并脱敏，不整文件复制。

### 10.1 BytePlus TLS 拟配置基线

Gateway 的 BytePlus TLS 接入方案已形成，但尚未在线实施或验证。完整步骤见 [tls-logcollector-guide.md](tls-logcollector-guide.md)。当前边界为：

- 复用 Crawler 已验证的主机 LogCollector 架构，不向 Go 进程加入 TLS SDK。
- Gateway 普通日志由 Go `slog.JSONHandler` 逐行输出 JSON；采集模式应为 JSON，而不是 Crawler 使用的 multiline。
- `main` 和 `test` 使用两条独立采集规则，写入同一个普通应用日志 Topic，并通过固定字段区分实例。
- 固定字段必须把共享生产依赖事实表达为 `environment=production-shared`，再用 `instance=main|test` 区分部署，不能把 `test` 标为安全隔离环境。
- 首次接入启用增量采集（`TailFiles`），只匹配两个当前活动文件，不匹配轮转文件，避免历史回灌、重复和费用失控。
- 完整 MQ 事件日志首期不接入 TLS。未来如确需接入，必须使用独立受限 Topic、单独 IAM、最短合规保留期和显式数据负责人审批；不能与普通日志混放。
- Crawler 的 `ap-southeast-1` endpoint 只是可复用候选。必须先在控制台确认 Gateway ECS 与目标 TLS Project/Topic 的 Region；若确认为 `ap-southeast-1`，LogCollector `2.4.2` endpoint 应包含完整 `https://` 协议。

在取得主机、host group、规则、heartbeat、发送计数和 TLS 查询证据前，只能称为“拟配置”，不能写成已接通。

飞书告警异步发送，默认 5 秒请求超时、相同 key 5 分钟抑制、内存队列有界；告警失败不会影响事件事务或 MQ ACK/NACK。

代码当前把 RabbitMQ 连接凭据以及飞书 webhook/签名配置直接编译在仓库中。本文不记录其值。它们属于需要治理的凭据风险，也意味着仅轮换 GitHub Secrets 不能完成这两类凭据的轮换。

主要告警包括：MQ 入 DLQ、RabbitMQ 断开、ACK/NACK 失败、consumer panic、用户补充失败、头像任务入队失败、头像/手工子系统启动失败、手工导入最终失败及进程异常退出。

## 11. 本地验证基线

2026-08-19 在干净 `main@f583e90` 上执行：

```text
go test -count=1 ./...
go build -trimpath -o <temporary-path> ./cmd/loa-data-gateway
<temporary-binary> --version
```

完整测试通过，覆盖 `alerting`、`archive`、`avatar`、`config`、`eventlog`、`importer`、`manualimport`、`model`、`postgres`、`rabbit` 和 `tosstore`。构建成功，本地未注入 ldflags 时版本为 `dev (unknown)`。

PostgreSQL integration tests 只有配置 `TEST_DATABASE_URL` 时才连接一次性数据库；本次普通测试不代表正式 PostgreSQL、TOS、RabbitMQ 或飞书已在线验证。

## 12. 故障定位主路径

### MQ 积压或没有消费

同时检查正式和测试两个 systemd 服务、RabbitMQ consumer 启动日志、连接重连告警、consumer 数量、ready/unacked 数量及队列 binding。由于是竞争消费者，不能根据单个实例没有收到消息判断整个链路停止。

### 消息进入 DLQ

从告警和事件日志取得 eventId、manifestPath、part filename 和失败分类；再核对 TOS manifest 是否完整、身份合同是否一致、哪个 part 失败，以及 PostgreSQL 是否已经提交前置 part。修复原因后再决定是否从 DLQ 重放或使用手工 manifest 导入。

### 数据库只有部分事件

按 manifest 列出的 part 顺序核对 object key 和数据库 `object_key`，确认失败发生在哪个 part。重放依赖事件 ID 幂等，但仍须检查两个 schema 是否保持同一 part 的一致性。

### 事件存在但用户或头像缺失

检查导入摘要中的 `users_failed`、`avatar_queue_failed`，再检查 `tiktok.user_info` 和 `tiktok.avatar_mirror_job`。这类失败可能已经 ACK，不能指望 RabbitMQ 自动重试；手工 manifest 导入也不会补用户或头像。

### 部署 Action 绿色但业务异常

核对实际二进制 `--version`、两实例日志、TOS读权限、事件 INSERT、DLQ、用户/头像子系统和真实 manifest 导入。现有 readiness 不覆盖完整数据面。

## 13. 仍需线上核验和补齐的信息

形成可执行 Skill 和正式操作手册前还缺少：

1. 正式和测试服务当前实际 commit、systemd 状态、运行时长和启动日志；服务器名、IP 和端口已经确认，不再列为拓扑缺口。
2. GitHub Actions 最近成功部署的精确 run ID/attempt/checkout SHA、self-hosted runner 状态和 Secrets 负责人。
3. RabbitMQ queue/DLQ 当前积压、consumer 数量、消息持久性及 DLQ 重放操作权限。
4. 两个事件 schema 的表结构、主键、索引、权限和数据量是否符合代码假设。
5. `tiktok.user_info`、`avatar_mirror_job` 的实际 schema、任务积压和失败分布。
6. TOS manifest/part 读取及头像写入权限的线上验证。
7. 已知日志文件在服务器上的实际存在性、文件权限、轮转/保留执行状态，以及飞书群访问权限、负责人和保留合规性；Gateway LogCollector 是否安装、TLS Region/Project/Topic、host group、规则下发、索引、保留期和查询结果也尚待线上核验。
8. 用户信息或头像在 MQ 已 ACK 后的补偿方法。
9. DLQ 重放、手工 manifest 导入，以及通过 GitHub 触发已知良好版本回滚的真实操作记录。
10. 固定在代码中的 RabbitMQ 和飞书凭据的轮换负责人和治理计划。
11. `test` 晋级 `main` 前需要满足的观测时长、最小真实事件样本、数据一致性检查项和 Go/No-Go 审批人。

这些缺口分别对应发布、维护、恢复和故障定位能力。下一阶段应先只读核验线上实例和资源，再分别形成发布 Runbook、DLQ/手工重放 Runbook、数据一致性检查 Runbook 和诊断 Skill。
