# OpenCreators API URL 与域名迁移基线

快照日期：2026-08-27（Asia/Shanghai）。本文记录新 OpenCreators 后端替换 legacy BattleMe 后端时，各环境和仓库的 API 入口约定、已完成状态与未完成风险。

这是一份可移植的运维快照，不是当前状态证明。处理具体故障或发布前，必须重新核对目标仓库的权威分支、workflow 实际注入值、最近部署 run、ALB 路由和只读在线探测。不得因本文存在某个 URL 就跳过当前核验。

## 核心结论

1. OpenCreators 新后端统一使用 servlet context path `/api`。域名迁移与 `/api` 路径迁移必须成对完成；只改其中一项会打到错误的 ALB host 规则或错误的应用路径。
2. Test 新 origin 为 `https://test-api-opencreators.loa.services`，Prod 新 origin 为 `https://api.opencreators.ai`。
3. UAT 尚未完成新入口固化。`https://uat-api.loa.services` 只是 legacy 配置线索，不能推导出一个可用的 OpenCreators UAT API；不得把 Test/Prod 规则机械套用到 UAT。
4. 不同消费者的 BaseURL 约定不同：`loa-mcp` 的后端 BaseURL 包含 `/api`；`loa_agent_lite` 和 `opencreators_app` 保存 origin，应由具体路径携带 `/api`。部分 OAuth/Webhook 回调仍有旧域名或缺 `/api` 的残留，不能假定迁移已全量完成。
5. 同一 ALB 地址可按 HTTP Host 路由到不同后端服务器组。旧、新域名即使解析到同一 CNAME/IP，也可能分别得到 `502` 和应用响应；不能仅凭 DNS 相同排除域名配置错误。

## 环境入口矩阵

| 环境 | OpenCreators origin | API base | Token 校验完整 URL | 状态与边界 |
|---|---|---|---|---|
| Local | 无独立公共入口；Agent Lite local profile 跟随 Test | 由消费者约定决定 | 跟随 Test profile | 仅适用于 Agent Lite 当前 profile，不得推广到其他仓库 |
| Test | `https://test-api-opencreators.loa.services` | `https://test-api-opencreators.loa.services/api` | `https://test-api-opencreators.loa.services/api/internal/ai/im/token/validate` | 新后端已部署并可达；legacy `https://test-api.loa.services` 在 2026-08-27 返回 ALB 502 |
| UAT | 未定义 | 未定义 | 未定义 | 仓库仍保留 `https://uat-api.loa.services` 和旧部署组线索，但新 `/api` 入口未建立或未验证；停止并先核验基础设施 |
| Prod | `https://api.opencreators.ai` | `https://api.opencreators.ai/api` | `https://api.opencreators.ai/api/internal/ai/im/token/validate` | 新后端 health 可达；legacy BattleMe 仍使用 `https://api.liveonair.ai` |

不要把 origin、API base 和完整 endpoint 混为同一个配置值。修改前先确认目标变量属于哪一列。

## 仓库迁移矩阵

| 仓库 | Test / Local | UAT | Prod | 配置约定与当前风险 |
|---|---|---|---|---|
| `loa-mcp` | PR #18 将 `BATTLEME_BACKEND_URL` 改为 Test API base，并将 `LOA_AUTH_URL` 改为完整 Token URL | 无 UAT 分支或配置 | PR #18 将两项切到 Prod 新入口 | MCP BaseURL **包含** `/api`；创建 PR 不等于部署，必须核验 PR 是否合并及部署 run 的实际 env |
| `opencreators_backend` | 新 Test 域名；全局 `server.servlet.context-path=/api`；部署已切到新后端组；Instagram/Waffo 回调仍有旧入口残留 | profile 仍写 legacy UAT 域名/无 `/api` 回调，workflow 仍有旧目录和旧后端组 | 新 Prod 域名；全局 `/api`；Waffo 回调仍为 legacy Prod 入口 | UAT 配置与新后端路径模型不一致；Local/Dev/UAT 及部分 Test/Prod 回调仍需逐键迁移，不能仅凭主域名完成判断 |
| `battleme_backend` | legacy `test-api.loa.services`，无全局 `/api` | legacy `uat-api.loa.services`，无全局 `/api` | legacy `api.liveonair.ai`，无全局 `/api` | 旧后端与新后端的 health 路径不同；不要用 BattleMe 路径模型验证 OpenCreators |
| `loa_agent_lite` | local/test origin 为 Test 新域名 | 无独立 profile | prod origin 为 Prod 新域名 | `LOA_API_BASE_URL` 只保存 origin，Token/User 路径常量携带 `/api`；`prod` 分支曾残留旧 `tiktok-user-api.ts`，核验分支漂移 |
| `opencreators_app` | `TEST_API_BASE_URL` 为 Test 新 origin，TikTok callback 带 `/api`，Instagram callback 仍缺 `/api` | UAT BaseURL 示例仍是 placeholder，deep-link 白名单仅保留 legacy UAT 域名，callback 示例未完成 `/api` 迁移 | `API_BASE_URL` 为 Prod 新 origin；已迁移 callback 带 `/api`，仍需逐项核验 | App BaseURL 只保存 origin；不能以白名单中出现域名或一项 callback 已迁移证明全部 API 可用 |
| `loa-im` | 当前 `test` 分支的 ap-server、message-service 已使用 Test 新完整 Token URL | 未发现可靠配置 | `main` 的版本化默认值仍指向 legacy Prod host 且缺 `/api`，可由 `LOA_AUTH_URL` 覆盖 | Test 已迁移，Prod 仍有默认值风险；必须核验部署分支和运行时覆盖值，不能只看某一个 YAML |

## 配置拼接规则

### `loa-mcp`

- `BATTLEME_BACKEND_URL`：使用 API base，值以 `/api` 结尾但不以 `/` 结尾。
- `LOA_AUTH_URL`：使用完整 Token endpoint，不依赖运行时再拼 `/api`。
- BattleMe/OpenCreators client 使用路径 join；回归测试应证明最终业务路径只出现一次 `/api`。
- 部署预检应同时锁定 Test 与 Prod 的两个变量。仅检查其中一个会留下半迁移状态。

### `loa_agent_lite` 与 `opencreators_app`

- BaseURL 使用 origin，不附加 `/api`。
- 已迁移的 Token、User、TikTok callback 等具体路径显式包含 `/api`；不要把该结论推广到所有 OAuth/Webhook。
- 修改共享 BaseURL 前，搜索所有手工拼接、URL constructor、测试 fixture、deep-link/associated-domain 白名单和分支特有文件。
- 已知残留包括 `opencreators_app` Instagram callback 缺 `/api`；应把它作为待核验/待迁移项，而不是照抄为正确模板。

### `opencreators_backend`

- 全局 context path 已是 `/api`，health 为 `/api/actuator/health`。
- 外部 OAuth/应用回调也必须与 `/api` context path 匹配；只改后端 context path 而不改回调会造成第三方回跳失败。
- 已知残留包括 Test 的 Instagram/Waffo、Prod 的 Waffo，以及 Local/Dev/UAT 的多项旧域名或无 `/api` 回调。迁移时必须逐键审计，不能以 TikTok callback 已修复代表全部回调已修复。

## 只读探测与故障定界

先探测 host 路由和应用 context path，再判断业务鉴权。不得使用真实用户 Token、签名密钥或业务 GUID 做基础可达性探测。

```bash
curl --connect-timeout 5 --max-time 10 -sS -o /dev/null -w '%{http_code}\n' \
  https://test-api-opencreators.loa.services/api/actuator/health

curl --connect-timeout 5 --max-time 10 -sS -o /dev/null -w '%{http_code}\n' \
  -X POST https://test-api-opencreators.loa.services/api/internal/ai/im/token/validate
```

2026-08-27 的观测基线：

- Test 旧 host 的根路径和 `/api` 路径均返回 `502`，响应方为 `volcalb`。
- Test 新 host 根路径返回 `404`，`/api/actuator/health` 返回 `200`；无凭据 Token POST 返回 `401`。后两个状态证明请求已到应用，`401` 不代表 Token 校验成功。
- Prod 新 host 根路径返回 `404`，`/api/actuator/health` 返回 `200`。
- UAT 根路径连续返回 `404`，`/api/actuator/health` 连续返回 `502`，因此不能宣称存在可用的新 UAT API。

结果解释：

- `volcalb 502`：优先检查请求 Host、ALB listener/host rule、目标服务器组和后端健康，而不是先怀疑客户端路径 join。
- 应用 `404`：host 已可能命中新后端，但路径或 context path 不匹配。
- health `200`：只证明该 host/path 到应用 health 可达，不证明 Token、Creator Products 或端到端业务成功。
- Token 无凭据 `401`：证明鉴权应用路径可达，不证明真实 Token/签名正确。

## 推荐诊断顺序

1. 从告警中记录实例、环境、upstream、method、route、状态码、时间窗口和响应方。
2. 在消费者仓库核对实际 BaseURL 语义：origin、API base 或完整 endpoint；同时检查部署 workflow 注入值。
3. 在后端仓库核对 context path、目标分支/SHA、部署端口、ALB 服务器组和最近成功 run。
4. 分别对旧 host、新 host 的根路径、health 和目标路径做无凭据只读探测；保存状态码和 `server` 响应头，不保存响应中的敏感字段。
5. 对比 DNS 只用于确认网络入口；若 CNAME/IP 相同，继续检查 Host 路由，不能提前结束诊断。
6. 只有消费者配置、部署 run 和在线探测三层证据一致时，才把故障归结为已修复。绿色 workflow 或进程 health 不能单独证明上游业务路径成功。

## UAT 停止条件

在以下证据齐全前，不得为 UAT 填入推测 URL，也不得发布 OpenCreators UAT：

- 明确的 OpenCreators UAT origin 与证书；
- ALB host rule 和独立、健康的后端服务器组；
- workflow 使用 OpenCreators 目录、服务名、端口和准确服务器组；
- `/api/actuator/health` 返回应用响应；
- App/OAuth callback、Token endpoint 和消费方 BaseURL 约定一致。

## 2026-08-27 事故与迁移证据

- `loa-mcp` Test run `32947212422` 部署 SHA `f5a2bb2`，实际仍注入 legacy Test host；这解释了路径已经适配但仍收到 ALB 502。
- `opencreators_backend` 提交 `d3ba7d87b3cac982b053861b5092499dba1eb489` 将 Test 部署切到新服务器组；Test run `33031139739` 成功部署新后端。
- `opencreators_backend` 提交 `a548fe58ab14a955148320147c542c56ded23d09` 固化 Test 新域名，提交 `edf48e06803b235390bfe8e94ca3d92f688df35f` 固化 Prod 新域名，提交 `d05c88b3f72497da2b2826b3fd0060783e01126b` 补齐其覆盖的 TikTok/Twitch 回调 `/api`；该提交不代表其他回调已全部迁移。
- `loa_agent_lite` 提交 `f10b995805b1796bc8c1c82bd933322374a9635c` 修复 main/Test 入口，提交 `2260b95d5aae534422138f8d4278d89bc6b0949e` 修复 Prod 入口。
- `loa-mcp` PR [Lighthunter-PTE-ltd/loa-mcp#18](https://github.com/Lighthunter-PTE-ltd/loa-mcp/pull/18) 提议同时迁移 Test/Prod host 与 `/api` 路径，并增加配置回归断言。使用本文时先核验该 PR 的当前状态和实际部署 run。
