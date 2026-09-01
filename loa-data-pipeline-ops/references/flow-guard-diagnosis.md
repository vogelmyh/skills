# OC Flow Guard 诊断

代码仓库：[Lighthunter-PTE-ltd/oc-flow-guard](https://github.com/Lighthunter-PTE-ltd/oc-flow-guard)。2026-09-01 已将 Git 历史中的冻结规格、架构、实施和运维记录与 `origin/main@943aee606d2d7c9a8fa6fdee312f980979e97e78` 的当前代码核对；GitHub run `33482448536` / attempt 1 对该 SHA 发布成功。使用本地 clone 时仍须先核验 origin、刷新权威 ref，并把代码、GitHub run、主机运行时、域名入口和业务验收分别举证。

OC Flow Guard 是部署发现与测试验收控制面，不在 Crawler → Gateway → Agent Lite 数据路径中。平台 `/readyz`、GitHub 同步成功、`no_assets` 或一条部署记录都不能证明 Agent Lite、Fan Radar 或其他业务链路通过。

## 当前静态运行合同

- 唯一公开入口：`https://auth.loa.services/oc-flow-guard/`。既有域名服务完成登录鉴权和前缀映射；应用自身只提供根路径 HTTP。
- 私网目标：`172.31.0.2:18080`；内部执行器/主机管理：`127.0.0.1:18081`。迁移时核实的域名服务代理源为 `172.31.0.7/32`，诊断当前网络时必须重新核验。
- 浏览器没有本地账号/密码/会话。所有上游已认证访问者使用统一 `gateway-operator`；公开 API 只能读取绑定，不能创建/修改绑定或取消系统自动运行。
- 主机管理复用独立 admin machine credential 和回环接口；执行器使用另一凭据。两者都不能经浏览器或业务端口调用。
- systemd：`oc-flow-guard-control.service`、`oc-flow-guard-executor.service`、一次性 `oc-flow-guard-network.service`。
- 活动根：`/www/typescript-server/oc-flow-guard/current`；数据为 `/var/lib/oc-flow-guard/control/state.sqlite` 的 schema 2；执行器工作目录和 journal 位于 `/var/lib/oc-flow-guard/executor`。
- 正式资产清单当前为空，静态版本为 `platform-0.1.0-empty`。因此绑定可以展示真实部署，但不会创建自动业务运行；`no_assets`/未验收是正确行为。

## 生产只读访问

当前请求明确要求平台运行时或日志诊断时，先按 [access-channel.md](access-channel.md) 将逻辑目标 `flow-guard-control` 绑定到当前使用者已获批的 SSH、BytePlus 会话或专用只读工具。它与 `gateway-shared` 共用 ECS，但必须限定到 Flow Guard unit、端口和目录；不得读取 Gateway 日志或业务 payload。

可使用的范围严格只读检查：

```bash
systemctl is-active oc-flow-guard-control.service
systemctl is-active oc-flow-guard-executor.service
systemctl is-active oc-flow-guard-network.service
systemctl show oc-flow-guard-control.service --property=ActiveState,SubState,NRestarts,ExecMainStartTimestamp,MainPID --no-pager
systemctl show oc-flow-guard-executor.service --property=ActiveState,SubState,NRestarts,ExecMainStartTimestamp,MainPID --no-pager
systemctl show oc-flow-guard-executor.service --property=ControlGroup --value
readlink -f /www/typescript-server/oc-flow-guard/current
stat -c '%a %U:%G %n' /www/typescript-server/oc-flow-guard/current /var/lib/oc-flow-guard/control /var/lib/oc-flow-guard/executor
stat -c '%a %U:%G %n' /etc/oc-flow-guard/secrets
ss -lntp '( sport = :18080 or sport = :18081 )'
journalctl -u oc-flow-guard-control.service --since '<start>' --until '<end>' --no-pager
journalctl -u oc-flow-guard-executor.service --since '<start>' --until '<end>' --no-pager
```

只读取 `current/deployment.json` 中的 `sourceCommit`、`bundleSha256`、`node`、`schema` 非秘密字段；不要打印完整配置、systemd credential 路径解析内容、secret 文件、执行器 claim token、journal 正文或不受限证据。`journal.json` 是否存在可以作为停止信号，但内容只在获批维护对账中最小读取，不应复制到聊天。

公开入口检查应使用正常浏览器/域名服务链路并保留 TLS 校验。未登录请求预期由上游拒绝或重定向登录；只有获批操作员才能验证登录后的 UI/API。不要通过直接访问 IP、伪造认证 header、关闭 TLS 校验或临时放宽 nft 来“证明”入口。

GitHub 只读检查：

```bash
git remote get-url origin
git fetch origin --prune
git rev-parse origin/main
gh run list --repo Lighthunter-PTE-ltd/oc-flow-guard --workflow deploy-main.yml --limit 10
gh run view <run-id> --repo Lighthunter-PTE-ltd/oc-flow-guard --json attempt,headSha,headBranch,event,status,conclusion,jobs,url
```

刷新 ref 会更新本地 Git 元数据；只有当前核验确有需要时执行。不要打开或转发完整 Action 日志；先用 run/job 元数据判断，再只裁剪必要步骤且脱敏。

## 证据层级

1. **仓库静态事实：** 当前 main 的 workflow、部署脚本、systemd 模板、配置 schema 和应用代码。
2. **GitHub run：** run/attempt、实际 `headSha`、job/step conclusion；证明 Action 实际覆盖到的构建和部署步骤。
3. **主机运行时：** `deployment.json`、进程 cwd/cmdline、systemd 状态/启动时间/重启数、监听端口、执行器新鲜心跳、SQLite schema/integrity。
4. **入口：** 域名服务未登录门槛、登录后页面/API、固定 Host/Proto/Origin、代理源和 18081 隔离。
5. **验收控制面行为：** GitHub progress、部署原因、自动运行关联、资产/执行器/证据状态。
6. **业务数据路径：** 真实业务资产执行及 Test/生产终点证据；只有这一层才能形成对应范围内的业务验收结论。

## 入口故障

### 未登录不再进入统一登录

先确认 DNS/TLS 和域名服务自身行为，再检查 `auth.loa.services` 的现有路由。Flow Guard 不拥有登录页面，也不应设置应用会话 Cookie。不得通过恢复本地登录、旧 `flow-guard.opencreators.ai` 规则或 ALB 直转绕过上游故障。

### 登录后 502

按顺序定位：控制服务是否 active、18080 是否监听准确地址、域名服务代理到 `172.31.0.2:18080` 的私网路由、实际 TCP 源地址是否仍在精确 nft/trusted-proxy 范围、`/readyz` 是否经该代理返回。2026-09-01 曾因只允许旧 ALB 网段而拒绝 `172.31.0.7`；该历史原因不能替代当前验证。

### `SECURE_ORIGIN_REQUIRED` 或写请求 `ORIGIN_DENIED`

应用要求可信 TCP 对端、`Host=auth.loa.services`、`X-Forwarded-Proto=https`，可选 `X-Forwarded-Host` 也必须匹配；非 GET/HEAD/OPTIONS 还要求 `Origin=https://auth.loa.services`。2026-09-01 曾因 TLS 在 ALB 终止后，内层 Nginx 用 `$scheme=http` 覆盖协议头而失败。应修复域名服务转发合同，不能放宽应用校验。

### 页面 200，但静态资源或 API 404

外部前缀由域名服务剥离/映射到应用根路径。当前前端使用相对 asset、API 和证据 URL；检查 `/oc-flow-guard/assets/...`、`/oc-flow-guard/api/...` 是否都进入相同 location 并在上游正确映射。不要在应用中重新硬编码公开前缀，也不要占用域名根的 `/assets` 或 `/api`。

## GitHub 发现与部署原因

控制台 `/api/overview` 的 `github` 只表示 poller 是否配置；`progress.fault`、`pending`、`lastFast`、`lastComplete` 才描述绑定同步状态。默认每 60 秒 tick，每 10 分钟进行完整回查；故障时进度可保持 fault/pending，而当前可读 revision 仍继续处理。

常见部署原因：

| 原因 | 含义与下一项只读检查 |
| --- | --- |
| `baseline_only` | attempt 在绑定启用边界前开始，只展示历史基线，不补跑。核对 `enabledAt` 与 run start。 |
| `mapping_mismatch` | workflow/path/event/ref 与该环境绑定不一致。读取当前 binding snapshot 和该 attempt 元数据。 |
| `deployment_pending` | run/attempt 尚未完成；等待同一 attempt，不拼接其他 attempt。 |
| `deployment_not_successful` | GitHub 原始结论非 success；这不自动证明服务不可用。 |
| `jobs_missing_or_ambiguous` | 必需 job 缺失或同名不唯一。核对该 attempt 的完整 jobs。 |
| `jobs_not_successful` | 必需 job 未 completed/success 或没有启动时间。 |
| `deployment_version_unconfirmed` | 绑定未确认本次 run SHA 即实际部署版本；不能创建业务验收。 |
| `no_assets` | 绑定有效但测试资产为空；只保存未验收部署事实，不创建自动运行。当前正式状态预期如此。 |
| `queued` | 已创建自动验收运行；仍须继续验证资产、执行结果、证据和目标版本。 |

常见 progress fault 如 `GITHUB_401/403/404/429`、`GITHUB_REPOSITORY_CHANGED`、`GITHUB_COVERAGE_GAP`、`GITHUB_RESPONSE`。先核对 installation 状态、selected repository、Actions/Metadata read、仓库稳定 ID、限流与分页范围。不得改用个人 PAT、增加写权限或删除旧 pending 记录来消除 fault。

旧 binding revision 的仓库若被删除、转移或撤出 App 授权，当前实现会保留旧 deployment 为 pending、保留 fault 且不推进完整同步标记，同时继续处理当前 revision 的可读 runs。看到旧 fault 时不能把当前 revision 也误判为完全停滞；分别核对 `lastFast`、`lastComplete`、pending identity 和新部署落库情况。

## 执行器、运行与证据

- 全局最多一个 occupied 运行，`queued`、`running`、`cancelling` 和终态分开。执行器领取即视为可能已经产生业务副作用。
- 控制服务重启不会自动撤销有效领取；失联、超时或取消会请求停止真实进程组。只有确认 cgroup/子进程为空后才释放不确定停止屏障。
- 执行器在领取请求前持久化 journal。重启发现不确定 journal 会保守暂停；不得删除 journal、换 boot ID 或直接把运行回队。获批维护须按 runId/bootId/requestId 对照数据库 claim/occupied 状态，并使用主机 `confirm-stopped` 合同处置。
- 正式资产来自受控 release 的 `src/assets/registry.ts` 构建结果，不接受浏览器/GitHub 提供的命令、路径、断言或 URL。当前为空时人工运行应被拒绝。
- `passed` 要求至少一个真实资产、完整必需结果/证据和可靠目标版本；进程退出 0、health、空结果、未知/重复项、超限或缺失证据都不能通过。
- 单附件 10 MiB，单运行证据 100 MiB；证据按摘要封存并归属运行。不要直接浏览文件系统路径代替授权下载。

## SQLite、容量与恢复

控制服务是唯一运行时 SQLite 写入者。数据库采用 WAL、`synchronous=FULL`，schema 必须为 2；正常启动不会创建丢失库、自动修复损坏库或迁移未知 schema。空间低于 `max(1 GiB, 文件系统 10%)` 时拒绝新增/领取运行，但应尽量保留只读诊断。

`admin check` 要求两个服务已经停止，不能为了普通诊断擅自运行。备份/恢复、`restore-quarantine`、schema 迁移、直接 SQLite 查询、证据清理和执行器对账都属于维护或变更边界；在准确展示停服影响、执行状态、备份范围、验证与停止条件并取得授权后才能执行。

还原旧副本不会恢复外部副作用，也不能证明恢复出的队列从未执行。恢复必须是 schema 2，隔离旧未结束任务、清除领取身份、设置新的恢复启用边界并重新补查 GitHub。旧 schema 1、认证表或含本地登录的 release 禁止恢复。

## Action 绿色但平台异常

依次核对 run/attempt 实际 SHA 和 deploy job、主机 `deployment.json`、两个 unit 的活动进程/cwd、executor heartbeat、18080/18081 监听及规范入口。早期 run `33408124778` 曾因只检查控制端而漏掉执行器不确定 journal；后续部署已增加停服前 journal 拒绝和新鲜心跳门槛。仍不能仅凭 run success 断言域名服务登录链路、GitHub poller、SQLite 数据或业务验收正常。

当前 workflow 没有任意历史 SHA 的常规回滚输入。若候选回滚不能由 GitHub Actions 精确检出且是已验证的无登录 schema 2 版本，应停止并报告发布控制面缺口；不得直接 SSH 切 `current`。

## 停止条件

- 域名服务实际代理源、Host/Proto/Origin 合同与配置冲突；
- 旧公网直达重新出现，或操作要求把 18080/18081 暴露给非批准来源；
- 活动 root、unit、进程或 `deployment.json` 不一致；
- schema 不是 2、数据库 integrity 未知/失败，或发现认证表/旧登录 release；
- 执行器 journal、claim、cgroup 或外部副作用状态不确定；
- GitHub App 需要新增凭据/权限，或 repository ID/绑定语义冲突；
- 修复需要删除部署/运行/证据、重置进度、迁移/还原数据库、停止/重启服务或修改网络/域名服务；
- 用户要求把 `no_assets`、health 或绿色 Action 当作业务通过。

## 交接

交接应包含：组件 `oc-flow-guard`、逻辑目标 `flow-guard-control`、目标时间窗、main/运行 SHA、GitHub run/attempt、活动 `deployment.json`、入口/运行时/同步/业务证据的层级、具体 fault/reason、是否存在 occupied/journal 屏障、已证明与未知结论，以及下一项最小只读检查。任何变更另列影响、回退条件、验证和即时授权。
