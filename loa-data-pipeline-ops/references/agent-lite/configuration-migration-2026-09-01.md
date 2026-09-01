# Agent Lite 配置归一化与发布验证（2026-09-01）

本文记录 2026-09-01 完成的 GitHub 配置归一化、运行时注入合同和发布证据。它是带日期的核验记录，不替代当前 workflow、GitHub Environment、部署脚本或服务器运行状态；后续操作前仍应重新只读查询。

## 变更结果

本轮删除了按环境后缀命名的 Repository Secrets、重复的 Repository model Variables、硬编码测试部署地址和旧生产地址 Secrets。Agent Lite 的环境差异现在由部署 job 绑定的 GitHub Environment 承载，运行时键名不再附加 `_TEST` / `_PROD`。

禁止把已删除的 Repository 配置补回为兼容 fallback。环境值缺失时应让部署失败并修复对应 Environment；不要依赖同名 Repository Variable 的静默回退。

## GitHub 配置所有权

### Environment Secrets

`lc-oc-test-lite` 与 `lc-oc-prod` 都持有以下无环境后缀的运行时密钥：

- `ATLAS_API_KEY`
- `MEM0_API_KEY`
- `SANDBASE_API_KEY`
- `VERCEL_API_KEY`

workflow 将 `ATLAS_API_KEY` 注入运行时键 `ATLASCLOUD_API_KEY`，其余名称保持不变。`OPENROUTER_API_KEY` 在两个 Environment 中仍存在，但 2026-09-01 的部署 workflow 没有引用它；不能据此把它列为当前发布必需项，是否保留应单独按调用证据治理。

### Environment Variables

两个 Environment 都持有模型路由：

- `LEO_AGENT_MODEL`
- `LEO_AGENT_FALLBACK_MODEL`
- `LIVE_RECAP_AGENT_MODEL`
- `LIVE_RECAP_AGENT_FALLBACK_MODEL`
- `TRANSLATION_MODEL`
- `TRANSLATION_FALLBACK_MODEL`

2026-09-01 只读核验时，Test 与 Prod 的路由值一致：

| Variable | 路由快照 |
| --- | --- |
| `LEO_AGENT_MODEL` | `Vercel-openai/gpt-5.6-luna` |
| `LEO_AGENT_FALLBACK_MODEL` | `SandBase-openai/gpt-5.6-luna` |
| `LIVE_RECAP_AGENT_MODEL` | `Vercel-openai/gpt-5.6-luna` |
| `LIVE_RECAP_AGENT_FALLBACK_MODEL` | `SandBase-openai/gpt-5.6-luna` |
| `TRANSLATION_MODEL` | `Vercel-tencent/hy-mt2-pro` |
| `TRANSLATION_FALLBACK_MODEL` | `Vercel-google/gemini-3.1-flash-lite` |

这些是带日期的配置事实，不是永久默认值。切换供应商或模型前后都应直接读取目标 Environment 的当前值。

部署目标同样属于 Environment Variables，而不是 Secrets：

- Test：`DEPLOY_A_HOST`、`DEPLOY_A_PORT`
- Prod：`DEPLOY_A_HOST`、`DEPLOY_A_PORT`、`DEPLOY_B_HOST`、`DEPLOY_B_PORT`

目标主机地址和端口是环境路由元数据，不是凭据。SSH 用户和私钥仍是组织级 Secrets，由目标分支选择 `UAT_TEST_SERVER_SSH_USER` / `UAT_TEST_SERVER_SSH_PRIVATE_KEY` 或 `PROD_SERVER_SSH_USER` / `PROD_SERVER_SSH_PRIVATE_KEY`。不要把这些身份材料迁入 Variables，也不要在 Skill 中记录其值。

### Repository Variables

Repository 层只保留由两个环境共享的 provider Base URL：

- `SANDBASE_BASE_URL`
- `ATLASCLOUD_BASE_URL`
- `VERCEL_BASE_URL`

2026-09-01 已删除 Repository 层的六个 model Variables。环境绑定 job 中 `${{ vars.NAME }}` 优先解析 Environment Variable；如果 Environment 缺少该键，则可能回退到同名 Repository Variable。删除重复 model Variables 的目的正是让错误的环境配置 fail closed。

## 统一模型路由合同

Chat Agent、Live Recap 和 Translation 都使用 `<Provider>-<model-id>` 描述路由，当前允许的 Provider 是 `SandBase`、`AtlasCloud`、`Vercel`。共享解析器按 Provider 选择连接参数：

| Provider | API key 运行时键 | Base URL 运行时键 |
| --- | --- | --- |
| `SandBase` | `SANDBASE_API_KEY` | `SANDBASE_BASE_URL` |
| `AtlasCloud` | `ATLASCLOUD_API_KEY` | `ATLASCLOUD_BASE_URL` |
| `Vercel` | `VERCEL_API_KEY` | `VERCEL_BASE_URL` |

Agent 和 Live Recap 使用 OpenAI-compatible Responses 路径；Translation 复用同一 descriptor、Provider 凭据和 Base URL 解析，再派生 Chat Completions endpoint。不要重新引入 `TRANSLATION_PROVIDER`、独立翻译 endpoint 或 `VERCEL_AI_GATEWAY_*`。

配置关口：

- Leo primary/fallback 的 Provider 必须不同。
- Live Recap primary/fallback 的 Provider 必须不同。
- Translation primary/fallback 完整路由必须不同；fallback 可以显式设为 `none`。
- 切换到已经接线的 Provider 时只改目标 Environment 的 model Variable；新 Provider 需要同时修改代码 allowlist、凭据/Base URL 接线、workflow 校验和 smoke，不能只改字符串。

## 部署注入与失败语义

`.github/workflows/deploy-on-merge.yml` 当前监听 `test`、`main` 的 `push`，使用 `github.ref_name` 和 40 位 `github.sha` 解析目标，checkout 准确 SHA 后再次核对 HEAD：

- `test` -> `lc-oc-test-lite` -> 单节点 Worker + Gateway + Gateway B。
- `main` -> `lc-oc-prod` -> 先部署 Prod A 的 Worker + Gateway，再部署 Prod B 的 Gateway。

部署前会检查所有必需键非空并验证 model descriptor。运行时配置以 NUL 分隔记录经 stdin 传到服务器，服务器脚本再次校验固定键集合和模型约束，再以 `0600` 权限原子更新 `.env`。更新时会移除已经废弃的 provider、翻译和旧 fallback 键，不保留兼容路径。

每个 Gateway 在重启后先检查 `/health`，再通过 `/api/translate` 发起真实翻译 smoke。Test 会检查 `18765` 和 `18766`；Prod A/B 分别检查本机 `18765`。

单机部署失败时，脚本会恢复 release 与部署前 `.env` 快照、重新安装依赖、重启并重新检查 Gateway health。它不会在 rollback 后重跑翻译 smoke，也没有 Worker readiness；`prod-a` 已成功而 `prod-b` 失败时也不会跨主机恢复 A。必须等待 Action 终态，再分别核验实际版本、Worker、Gateway、翻译和数据路径。

## 发布证据

分支与提交：

- `dev@2a0d851439449a993365c7c421940f494e4d9a4e`
- `test@8b507550593d4ea9cfd65389f4a1d03fd253e4a5`
- `main@ffb8b88200ea2c49c23ef5fe180b2e69f6ff34e4`

GitHub run：

- Test `Deploy on merge` run `33481379194`：event `push`，head SHA `8b50755...`，Resolve、Build、Check、Test、Leo runtime smoke 和 Deploy 全部成功。
- Prod `Quality` run `33482168149`：head SHA `ffb8b88...`，成功。
- Prod `Deploy on merge` run `33482168214`：event `push`，head SHA `ffb8b88...`，Resolve、Build、Check、Test、Leo runtime smoke 和 Deploy 全部成功。
- Prod Environment deployment `6196599367`：状态 `success`。

发布后的范围严格运行时核验显示：Test 三个服务、Prod A 的 Worker/Gateway、Prod B 的 Gateway 均为 active 且 `NRestarts=0`；目标 Gateway health 返回 HTTP 200，真实翻译 smoke 通过，检查窗口内相关 error journal 数为 0。

这些证据证明对应 SHA 的 CI、workflow 部署步骤、进程状态、浅 health 和翻译调用在该时点通过；不证明 Worker readiness、RabbitMQ/PostgreSQL/Mem0、其他模型路由或 Fan Radar 端到端数据路径健康。

## 后续核验规则

1. 只查询配置键名和作用域，不读取或输出 Secret 值。
2. 发布前同时检查 Repository Variables、目标 Environment Variables/Secrets 和 workflow 引用，避免重复配置形成静默 fallback。
3. 改 Provider 时核对 model descriptor、对应 API key、Base URL 和调用协议；当前模型恰好使用某 Provider，不等于解析逻辑可以被写死。
4. 地址迁移后不得恢复硬编码测试主机或 `LC_OC_PROD_*`；目标 Environment 缺少 `DEPLOY_*` 时部署应失败。
5. 分支推进、Action success、Environment deployment、运行时状态和数据路径结论必须分层记录。
