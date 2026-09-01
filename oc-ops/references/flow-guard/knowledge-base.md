# OC Flow Guard 接管知识底稿

## 1. 资料、仓库身份与证据基线

代码仓库：[Lighthunter-PTE-ltd/oc-flow-guard](https://github.com/Lighthunter-PTE-ltd/oc-flow-guard)，私有，默认分支 `main`。本地 clone 使用前以 `git remote get-url origin` 核对身份；旧个人远端 `vogelmyh/oc-flow-guard` 只属于历史来源，不是权威发布仓库。

本底稿在 2026-09-01 使用以下材料形成：

- 工作区已删除但 Git 对象中仍存在的 `.codex/design/platform-skeleton/SPEC.md`（FROZEN）、`.codex/design/gateway-auth-removal/SPEC.md`（FROZEN）、`.codex/design/typescript-server-layout/SPEC.md`（FROZEN）和 `.codex/design/auth-path-entry/SPEC.md`（SUPERSEDED）；
- Git 历史中的 `docs/architecture.md`、`docs/implementation.md`、`docs/operations.md` 及实现候选记录；这些文档在 `origin/dev@903a5af4945352f21ff3d211f22b558ca3f03d2e` 可读；
- `origin/main@943aee606d2d7c9a8fa6fdee312f980979e97e78` 的当前源代码、workflow、部署脚本、systemd/config 模板和测试；
- 2026-09-01 GitHub 只读查询：默认分支仍为 `main`，最新 `Deploy platform main` run `33482448536` / attempt 1 对准确 main SHA 成功。

工作区删除不改变历史文档的证据价值，也不表示应恢复这些文件到当前项目。旧文档包含设计演进和带日期运行快照；与当前代码冲突时，以当前 main 静态事实为准，并把历史 ECS/入口结果明确标记为运行时快照或操作员确认。任何快照都不能证明当前线上状态。

冻结规范的覆盖关系：

1. 平台骨架 SPEC 继续约束 GitHub 发现、SQLite、队列、执行器、证据和恢复。
2. Gateway auth removal SPEC 覆盖并删除平台骨架中的本地账号、密码、会话、角色、公开绑定写面和直接 ALB 入口。
3. TypeScript layout SPEC 约束活动代码根与发布布局。
4. Auth path entry SPEC 已被替代，只能作为历史 URL/基础设施线索，禁止恢复其中的本地登录和 ALB Path 直转方案。

## 2. 工程定位与能力边界

OC Flow Guard 是部署发现与测试验收平台，不是业务服务，也不在 Crawler → TOS/MQ → Gateway → PostgreSQL → Agent Lite/Fan Radar 数据路径中。它提供：

- React 控制台，展示 Test/生产两个业务环境的工作台、部署、运行、报告、证据和观察；
- 专用 GitHub App installation 身份，只读轮询已登记仓库的 workflow run/attempt/jobs；
- 显式部署绑定，把稳定仓库、workflow、事件/ref、环境、必需 job、SHA 语义和固定测试资产关联；
- SQLite 持久化的部署事实、轮询进度、全局串行任务、运行结果、证据索引和审计；
- 独立执行器，通过受认证回环接口领取受控 release 中的固定资产，运行子进程、心跳、停止、提交结果与证据；
- 受保护的主机管理入口，用于数据库初始化/检查/迁移/恢复隔离、绑定维护、系统运行取消和停止确认；
- GitHub 部署结果与业务验收结果分离：部署成功即结束，平台异步处理验收，不回写 GitHub，也不自动回滚。

当前正式资产清单是空数组，版本 `platform-0.1.0-empty`。因此当前可验证真实 GitHub 部署发现和平台控制合同，但不会执行 Agent Lite 或其他业务测试。`no_assets`、未验收和人工运行禁用是正确状态；不得加入演示资产、空运行或以退出码/health 制造通过。

明确不具备：

- 本地浏览器账号、密码、会话、用户角色或账号管理；
- 浏览器写部署绑定或取消系统自动运行；
- GitHub workflow dispatch/rerun、状态回写、发布或回滚权限；
- 任意命令、脚本、URL、断言或动态插件执行；
- 容器、多机高可用、外部数据库/消息队列、TOS/异机备份、自动归档/清理；
- Test/生产业务账号和数据生命周期、Markdown 自动解析执行；
- 自动重试业务验收、自动修复业务数据或自动回滚。

## 3. 运行组件与信任边界

### 控制服务

`oc-flow-guard-control.service` 运行 Fastify 控制/API、React 静态页面、GitHub 轮询、调度、SQLite 和证据索引。它是唯一运行时数据库写入者，拥有 executor/admin machine credential 和可选 GitHub App credential；运行账号为 `flowguard-control`，不得读取执行器工作目录或修改代码/unit。

公开业务监听为配置中的精确 IP `172.31.0.2:18080`，不能绑定 `0.0.0.0`。内部监听为 `127.0.0.1:18081`。控制服务启动后每秒 sweep 运行超时/失联状态，每 60 秒触发一次 GitHub poller；停止时先关闭两个 listener，等待当前 poller 完成再关闭数据库。

### 执行器

`oc-flow-guard-executor.service` 运行固定资产 worker，账号 `flowguard-executor`。它没有 SQLite、GitHub App、admin credential 或控制私有目录权限。子进程使用 Node 执行受控 registry 的 entry，不接收外部命令。执行器 journal 在领取请求前持久化，用 bootId/requestId/runId/token 对账不确定执行。

systemd 对两个服务使用不同账号、`NoNewPrivileges`、空 capability set、只读系统、私有 tmp/device、cgroup 级停止和资源上限。模板 MemoryMax 为控制 768 MiB、执行器 1 GiB；当前模板 CPUQuota 为 100%，历史主机曾有 50% drop-in，诊断必须读取实际 unit/drop-in，不能从模板推断运行值。

### 网络 unit

`oc-flow-guard-network.service` 是 root 运行的一次性 nft loader，只管理独立 `inet oc_flow_guard` 表；不得 flush 主机完整 ruleset。当前模板把 18080 收敛到历史核实的域名服务代理 `172.31.0.7/32`，把 18081 收敛到 loopback。来源地址迁移必须重新验证，不能直接复制历史值或放宽全 VPC。

## 4. 公开入口、身份和 HTTP 合同

唯一规范 URL：

```text
https://auth.loa.services/oc-flow-guard/
```

既有域名服务负责 TLS、用户登录和外部 `/oc-flow-guard/` 前缀到应用根路径的映射。Flow Guard 自身服务 `/`、`/api/...`、`/healthz`、`/readyz`，不实现 public base path，不创建专用 ALB Path 规则。前端使用相对静态/API/证据 URL，使浏览器请求保持在外部前缀，由域名服务剥离后交给应用根路径。

安全校验顺序：

1. TCP 对端必须匹配 `trustedProxies`；否则 `PROXY_REQUIRED`。
2. 健康路由之外，`Host` 和可选 `X-Forwarded-Host` 必须匹配配置 origin 的 host，`X-Forwarded-Proto` 必须为 `https`；否则 `SECURE_ORIGIN_REQUIRED`。
3. 非 GET/HEAD/OPTIONS 必须带精确 `Origin=https://auth.loa.services`；否则 `ORIGIN_DENIED`。
4. 应用设置 CSP、nosniff、no-referrer 和 no-store，不接受上游个人身份 header，也不设置应用会话 Cookie。

所有经域名服务认证的用户共享固定主体 `gateway-operator`：可读两个业务环境，可创建手工运行，可取消 actor 同为 `gateway-operator` 的手工运行。平台无法提供个人归属/个人审计；这是已确认边界。浏览器不能写绑定、不能调用内部接口、不能取消 system run。

公开 API：

| 路由 | 能力 |
| --- | --- |
| `GET /healthz`、`GET /readyz` | 最小存活/SQLite 可读就绪；不探测 GitHub、执行器或业务。 |
| `GET /api/environments`、`/api/assets`、`/api/overview` | 环境、受控资产、运行/同步/容量/执行器概况。 |
| `GET /api/bindings` | 只读绑定；没有公开 POST/PATCH。 |
| `GET /api/deployments`、`/api/deployments/:id` | GitHub 原始事实、识别原因和自动运行关联。 |
| `GET/POST /api/runs` | 查询或以 `gateway-operator` 创建手工运行；创建必须有 `Idempotency-Key` 和已知资产。 |
| `GET /api/runs/:id`、`/report` | 运行、单项结果和证据元数据。 |
| `POST /api/runs/:id/cancel` | 只取消统一主体的手工运行。 |
| `GET /api/artifacts/:id` | 按运行归属下载已封存证据，附件响应、禁 MIME 嗅探。 |
| `GET /api/observations` | 从真实运行 item result 投影观察；无资产时为空。 |

## 5. 内部接口与主机管理

内部 Fastify listener 只接受 loopback、准确 Bearer machine credential，且拒绝 Cookie。执行器与 admin 使用不同凭据。

执行器内部操作：`claim`、`heartbeat`、`result`、`artifact`。证据上传要求 run/boot/claim identity、服务端 upload key、SHA-256 和允许的 MIME；单上传 body limit 为 10 MiB。

主机 admin 操作：

- 列出、创建、更新/停用部署绑定；使用与应用相同的 schema、revision 冲突和启用边界；
- 取消 system run；
- 在执行器服务已停止且 cgroup 为空后确认不确定运行已经停止；
- 初始化新 schema 2 数据库、停服 check、显式 schema 1→2 认证清理迁移、还原副本后的 quarantine。

CLI 命令名为 `init`、`check`、`migrate-auth-schema`、`restore-quarantine`、`bindings`、`create-binding`、`update-binding`、`cancel-system-run`、`confirm-stopped`。绑定 JSON 只能从受保护 stdin 提供；不要把 admin token、运行 token 或敏感字段放到命令行/日志。`check`、迁移和 restore 要求服务停止，不能用于普通在线探活。

## 6. SQLite 数据与不变量

当前 schema 2 表：

| 表 | 责任 |
| --- | --- |
| `meta` | schema、restoreBoundary、executorLastSeen 等平台元数据。 |
| `environments` | 固定业务 `test`/`prod` 启用状态。 |
| `bindings` | 带 revision/启用边界的部署映射快照。 |
| `deployments` | 仓库/run/attempt/environment 唯一的 GitHub 部署事实。 |
| `progress` | 每 binding 的 fast/full 游标、pending、fault。 |
| `runs` | 运行状态、快照、领取、停止与结果；partial unique index 保证全局一个 occupied。 |
| `idempotency` | actor/key 到人工/自动运行的幂等映射。 |
| `claims` | bootId/requestId 到 run 的领取重传映射。 |
| `artifacts` | run/upload key 唯一的封存证据元数据。 |
| `audit` | 机器/统一主体的动作、目标、时间和结果。 |

不存在 `users`、`sessions`、`limits`。发现这些表或 schema 1 表示旧认证数据/版本回流，应停止。数据库使用 Node 内置 `node:sqlite`、WAL、`synchronous=FULL`、foreign keys 和 5 秒 busy timeout。启动要求 SQLite 至少 3.51.3；历史 ECS 实际为 3.53.4。

普通启动不会创建缺失数据库，只有明确 `init` 可以新建 schema 2。启动会拒绝不兼容 schema 和 quick_check 失败。容量保护为 SQLite 所在文件系统可用空间低于 `max(1 GiB, 10%)` 时拒绝新增/领取工作，不以自动删除历史腾空间。

## 7. GitHub App、绑定与同步

GitHub App 只请求 installation 的 `actions:read`、`metadata:read`。JWT 使用 9 分钟内的短期签名，installation token 提前 60 秒刷新；读取路径白名单限制在目标 repo 和 actions。GET 对 401、5xx 最多三次有界退避；401 会清 token。403/429 尊重 Retry-After/rate reset 并至少暂停 60 秒。没有 PAT/OAuth fallback。

2026-09-01 非秘密身份快照：App `OC Flow Guard`，App ID `4787546`，Installation ID `158109270`，selected repositories。私钥只通过 control unit credential 提供，执行器不可读；诊断只核验 installation/权限/文件元数据，不读取 key/token。

绑定字段包括：稳定 repository ID、owner/name、workflow ID/path、允许 event/ref、唯一 environment、必需 job、版本来源说明、SHA 是否已核验、asset IDs、revision、enabledAt。映射改变或禁用后启用会重置启用边界；仅资产变化不把旧部署自动重跑。公开控制台只读，变更走 host admin。

轮询行为：

- 每 60 秒快速查询，从 lastFast/启用边界向前重叠 120 秒；
- 至少每 10 分钟完整查询，从 lastComplete/启用边界向前覆盖 31 天，以捕获旧 run 的新 attempt；
- 每页 100，GitHub 结果达到 1000 时按创建时间递归切片；同秒仍达到上限、分页集合变化、去重数不匹配或 attempt/job 不完整时产生 `GITHUB_COVERAGE_GAP`，不推进完整游标；
- 逐个 attempt 读取准确 run 和完整 jobs，不拼接不同 attempt；attempt 安全上限为 100，job 安全上限为 10,000；
- 已保存但未处理的 deployment 使用它自己的 binding snapshot 继续补取。旧 snapshot 仓库不可读时保留 fault/pending，不推进 lastComplete，但当前 revision 的可读 runs 仍继续入库；
- 部署事实和责任先落库，再推进 progress；数据库/容量失败不能只在内存标记处理完成。

部署原因按顺序判断：启用前 `baseline_only`；身份不符 `mapping_mismatch`；未完成 `deployment_pending`；非成功 `deployment_not_successful`；必需 job 缺失/歧义或失败；版本未确认；资产为空 `no_assets`。只有全部条件满足且资产非空才创建 system run；创建失败按稳定错误码写回 deployment，不改 GitHub。

当前 Agent Lite 绑定快照：repository ID `1238648790`，workflow ID `342003207` / `.github/workflows/deploy-on-merge.yml`，event `push`，Test ref `test`、Production ref `main`，必需 job `Deploy merged revision`，SHA 语义已核实。两条资产清单为空。

## 8. 调度、执行、结果与证据

所有业务环境共用一个 SQLite 队列和一个执行器，按创建顺序领取，全局最多一个 occupied。串行不等于外部依赖隔离，也不保证外部副作用恰好一次。

默认参数：整次运行 30 分钟；执行器心跳 10 秒，60 秒失联触发对账；停止宽限 10 秒，之后强制停止并确认进程组回收。运行状态为 `queued`、`running`、`cancelling`、`passed`、`failed`、`unverified`、`cancelled`。

领取保存 runId、bootId、token、requestId 和 deadline；同 boot/request 重传返回同一 run。目标或资产在执行前再次观察，版本变化会终结为未验收。执行器按资产顺序记录 before/after observation、解析协议 1 结果、上传证据并提交完整 item result。

结果通过条件：至少一个真实资产、所有必需 item 完整且通过、目标版本可归属、必需证据已封存。明确断言失败为 `failed`；执行器中断、超时、结果/证据缺失、版本不明为 `unverified`。后续项异常不能隐藏已经完成的失败。终态不会被迟到结果或复验覆盖；人工复验创建新 run。

取消/完成竞争按控制服务事务接受顺序。取消、失联和超时会停止受控进程组，但不能撤销已经发出的外部请求。停止未确认时即使运行已标未验收，也继续占用全局屏障，禁止冲突执行。

证据先写临时普通文件，验证长度/摘要、fsync 并封存；拒绝路径穿越、symlink 越界和未封存下载。普通 JSON 1 MiB，单附件 10 MiB，单运行累计 100 MiB。数据库只保存元数据和相对标识。

## 9. 发布控制面与目录

唯一发布入口是仓库 `.github/workflows/deploy-main.yml`：

- `main` push 和受限 workflow dispatch，job 只在 `refs/heads/main` 执行；`dev` 不部署；
- `loa-self-hosted` runner，30 分钟 job 超时，concurrency `oc-flow-guard-main`、不取消已运行部署；
- 精确 checkout `github.sha`，Node 24.20.0/npm 11.19.0；执行 `npm ci`、typecheck、build、Python 部署测试、Playwright Chromium、Node 测试和 production prune；
- 使用组织 UAT/Test SSH secrets 连接固定 `172.31.0.2`，严格 known_hosts，临时 key/远端 stage 在退出清理；不需要 BytePlus AK/SK；
- tar 包只含 `dist`、`deploy`、package manifests 和 production node_modules，排除 pycache/pyc/create-admin；包有 SHA-256。

远端 `scripts/deploy-release.py` 只由 Action 调用。活动布局：

```text
/opt/node-v24.20.0
/www/typescript-server/oc-flow-guard/
  packages/
  releases/<full-commit>-<bundle-sha-prefix>/
  current -> releases/<active>
  deploy.lock
/etc/oc-flow-guard/
/var/lib/oc-flow-guard/control
/var/lib/oc-flow-guard/executor
```

脚本校验 root 身份、归档路径/类型/symlink、bundle hash、Node、schema 2、lockfile 和 release manifest。已存在同一 release 只有在 current 和摘要都一致时幂等返回。新 release 解包后先停 executor；若 journal 存在立即停止切换并让 control 保持运行。随后停 control、确认两个 cgroup 空、以旧 active admin 执行数据库 check、原子替换 current、启动两个服务，最后等待本次启动后的 executor heartbeat。

一次性 `--migrate-auth-layout <private-/32>` 只用于 2026-09-01 从 `/opt`/schema 1/旧登录迁移。它要求旧公网入口已用 root:0600 marker 独立证明关闭。迁移和 finalizer 已完成，普通发布不得再次使用；旧 `/opt/oc-flow-guard`、认证备份和 marker 已删除。

当前 workflow 没有任意历史 SHA 的常规回滚入口。直接 SSH 切 symlink、复制 release 或重启服务违反控制面约束。回滚候选必须是已验证无登录/schema 2 release，并能通过 Action 绑定准确 SHA；否则先补齐控制面设计，不执行。

## 10. 入口和发布的 2026-09-01 历史实证

GitHub 当前证据：main SHA `943aee606d2d7c9a8fa6fdee312f980979e97e78`，run `33482448536` / attempt 1 / job `99774875185` success；job 覆盖精确 checkout、构建/测试和部署 step。历史实施记录的 bundle SHA-256 是 `bf7f3e01b98b7b84e63d91336f7fb14862364059aef0e97ed1f3ef40381dd5aa`。

带日期主机证据记录：活动代码在 TypeScript 根，schema 2、认证表 0、integrity ok；control/executor/network units active，执行器有新鲜心跳。旧 `flow-guard.opencreators.ai` 的 443/80 直达已删除，旧根/五份迁移备份/marker 已 finalizer 清理。

入口证据记录：未登录规范 URL 进入统一登录；登录后页面、CSS、JS、overview/assets/runs API 为 200；缺少合法 Origin 的写请求为 403。早期 `SECURE_ORIGIN_REQUIRED` 来自域名服务在 ALB TLS 终止后用内层 `$scheme=http` 覆盖协议头，随后只对 Flow Guard HTTPS location 固定 `X-Forwarded-Proto=https` 并完成浏览器验收。

GitHub 发现证据记录：Agent Lite Test/Production 各 40 条、共 80 个唯一 deployment identity；78 个 baseline、1 个对侧 mapping mismatch、1 个 Production `no_assets`；两个 progress 当时 fault null/pending 0，重复轮询游标前移而记录不增长，自动运行 0。

这些证据证明当时平台发布、入口、发现和空资产合同；不证明当前 ECS 仍运行同一 release，也不证明 Agent Lite、Test/生产或 Fan Radar 业务通过。

## 11. 维护与恢复

本地代码基线命令：

```bash
npm ci
npm run typecheck
npm run build
npm test
python3 -m unittest tests/deploy_release_test.py
```

测试使用临时 SQLite、GitHub HTTP fixtures、真实本机子进程和 Chromium，不访问业务服务。正式 registry 必须与受控测试用例合同一致；当前没有业务资产。生产发布前以目标 SHA 的 workflow 实际命令为准，不从本文复制旧依赖/步骤。

备份没有调度或远端副本。维护流程要求明确授权后停两个服务、确认 cgroup/子进程停止、执行 check/WAL checkpoint、复制完整 SQLite 状态及对应证据、记录 active release/schema 和校验摘要，在独立受保护目录验证可打开/integrity/证据摘要。WAL/SHM 存在时不能只复制主 DB。秘密单独管理。

还原不是普通重启：只接受已校验 schema 2 副本；停服并确认执行器后恢复权限，执行 restore-quarantine，清除领取身份、隔离未结束任务、设置新恢复边界，隔离旧 executor journal，核对绑定和当前目标，再启动。GitHub 只补回仍可查询的部署事实，不能还原运行证据或证明外部操作未发生。

空间不足时停止新运行，不自动清理。任何手工删除部署、运行、audit、artifact、progress、package 或 release 都需要精确范围、保留/去重影响、回退/验证和单独授权。当前无异机副本，不承诺固定 RPO/RTO 或整盘恢复。

## 12. 故障定位主路径

### 入口不可用

区分 DNS/TLS、域名服务登录、上游 path mapping、私网连通/nft、控制 service/listener 和应用 Host/Proto/Origin 校验。不要恢复本地登录或旧 ALB 直达。详细顺序见 [../flow-guard-diagnosis.md](../flow-guard-diagnosis.md)。

### GitHub 部署没有出现

先确认 poller configured、binding enabled/revision、installation 仓库授权及稳定 ID，再看 lastFast/lastComplete/pending/fault、run event/ref/workflow 和每个 attempt/jobs。旧 revision fault 与当前 revision ingestion 分开判断；不删除 pending 或重置游标制造绿色。

### 部署出现但没有自动运行

读取 deployment `reason`。当前资产为空时 `no_assets` 是预期；baseline/mapping/job/version 原因各自需要不同证据。不得手工造运行绕过部署识别或把当前版本结果挂到旧部署。

### 执行器离线或队列卡住

检查 control/executor unit、启动时间/重启数、executorLastSeen、occupied run、executor journal 是否存在、cgroup/进程和运行 stop 状态。journal/claim 不确定时保持暂停，先对账；不能只重启或删除 journal。

### Action 成功但入口/平台异常

核对 run/attempt SHA、主机 `deployment.json`、实际 current/cwd、两个 unit/new heartbeat，再单独核对域名服务入口和 GitHub poller。绿色 run 不证明浏览器登录链路或数据状态。

### SQLite 或证据异常

在线只读查看容量/错误信号；check/restore/直接 DB 操作需要停服和授权。区分数据库不可用、schema 冲突、capacity threshold、artifact 文件缺失/摘要不符和权限错误，不以重建空 DB 或删历史修复。

## 13. 当前知识缺口与维护要求

- 当前 ECS 活动 SHA、systemd 状态、执行器 heartbeat、域名服务入口和 GitHub progress 需要按每次事件重新核验；本底稿只有 2026-09-01 快照。
- 没有当前集中日志/TLS 接入记录；核心诊断入口是范围限定的 journald、GitHub metadata 和控制台 progress。若新增集中日志，必须单独设计字段、敏感数据、Topic/IAM、保留和验收。
- 正式业务资产仍为空。后续每个新需求必须先有产品与研发共同确认的结构化 Markdown 源用例，再由开发手工实现、隔离测试并在 `src/assets/registry.ts` 显式注册；版本、环境、证据和步骤 ID 必须可追溯。不能从旧原型示例生成业务用例。
- 当前发布控制面缺少任意已核验历史 SHA 的直接回滚入口；需要回滚时先判断能否通过受保护主干和 Action 精确检出目标，不可用 SSH 替代。
- 共享 ECS 同时承载 Gateway。Flow Guard 维护必须限制到自己的 unit、nft 表、端口和目录，并核对不会改变 Gateway 服务/文件/网络；同主机故障是共同风险。
