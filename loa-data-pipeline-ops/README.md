# loa-data-pipeline-ops

运维、发布、回滚和诊断 LOA Crawler-to-Gateway-to-Agent-Lite 数据链路，并保留运行环境、组件故障、端到端排查及 OpenCreators API 入口迁移经验。

## When to use

适用于 `loa-glabal-crawler`、`loa-data-gateway`、`loa_agent_lite` 或 `loa-mcp` 的部署、GitHub Actions、BytePlus 运行状态与日志、告警，以及 RabbitMQ、TOS、PostgreSQL、Fan Radar 数据路径和 OpenCreators/BattleMe API 域名、BaseURL、`/api` 前缀、Token 校验、ALB 502 故障。不用于无关的 LOA 应用层工作。

## Invoke

```text
$loa-data-pipeline-ops
```

调用时提供目标组件、环境、症状或操作目标以及已知时间窗口。具体的请求分类、授权边界、安全约束、参考资料路由和停止条件以 [`SKILL.md`](./SKILL.md) 为准。

## Contents

- `SKILL.md`：Codex 指令入口、任务路由、授权边界与不可违背的运维约束
- `references/environment.md`：环境、分支、主机、端口、服务和日志位置快照
- `references/access-channel.md`：共享逻辑目标、网络拓扑，以及每位使用者如何绑定自己的获批访问通道
- `references/deployment-control-plane.md`：GitHub Actions 发布控制面、组件映射与不可替代的安全边界
- `references/crawler-diagnosis.md`：Crawler 告警、采集、TOS、MQ 发布与日志排查
- `references/gateway-diagnosis.md`：Gateway 的 MQ、TOS、PostgreSQL、DLQ、导入与日志排查
- `references/agent-lite-diagnosis.md`：Agent Lite Worker/Gateway、应用日志与告警排查
- `references/end-to-end-diagnosis.md`：Fan Radar 和组件未知故障的端到端定界
- `references/opencreators-api-domain-migration-2026-08-27.md`：OpenCreators/BattleMe 各环境与各仓库 API 域名、路径约定、迁移状态和 ALB 排障基线
- `references/crawler/`：Crawler 详细知识底稿、交接与 MQ 契约、TLS 架构及发布实证
- `references/gateway/`：Gateway 详细知识底稿与 TLS 人工实施手册
- `references/agent-lite/`：Agent Lite 详细知识底稿、运行快照与 TLS 人工实施手册
- `assets/agent-lite-tls/`：Agent Lite journald 导出、systemd 与 logrotate 的已审计安装文件
- `agents/openai.yaml`：界面展示元数据
- `README.md`：面向维护者的概览，不参与运行

该 skill 是可独立迁移的完整单元。`references/` 中的文档是与入口指令配套的运维知识快照，`assets/` 保留已审计的安装文件；迁移或安装时应与 `SKILL.md` 一起保留。

共享版本只固化逻辑目标、云资源事实、网络拓扑、服务与安全边界，不依赖维护者个人的仓库路径、SSH alias、SSH 用户或身份文件。每位使用者应按 `references/access-channel.md` 在自己的执行环境中绑定已获批通道；Skill 不分发凭据或个人 SSH 配置。
