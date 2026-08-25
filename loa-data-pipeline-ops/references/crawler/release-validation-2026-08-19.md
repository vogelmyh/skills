# Crawler 生产发布与回滚验证记录

验证日期：2026-08-19
生产操作窗口：用户明确授权
业务代码变更：无

## 1. 验证目的

把 Crawler 发布知识从 workflow 静态推断升级为生产实证，并核验当前无需修改代码即可执行的回滚方式。本文不记录主机地址、SSH 密钥或其他敏感配置。

## 2. 发布前基线

- 权威分支：`origin/prod`
- 目标提交：`1807b9411e398ca3ba2221e4e7a45b03005c0279`
- 提交说明：`Merge pull request #27 from Lighthunter-PTE-ltd/codex/fix-euler-rate-limit`
- 发布前没有正在运行的同 workflow job。
- 最近一次成功生产发布 run：`32033664076`。
- 该历史 run 的日志确认实际 checkout 的是上述 `prod` merge commit，而不是 PR head SHA；72 项测试通过，最后返回 `health=UP`。
- 仓库存在生产部署 SSH Secret；没有仓库级生产部署变量，workflow 使用其生产默认目标。本文不记录目标值。

用户确认当时生产可用于发布流程测试。受访问条件限制，发布前没有独立取得服务器 JAR 校验值、PID、systemd 状态、活跃连接数或 `/api/monitoring/status` 快照。

## 3. 同 SHA 生产发布

触发方式：

```text
workflow: .github/workflows/deploy.yml
ref: prod
input environment: prod
```

运行证据：

- run ID：`32241855223`
- attempt：`1`
- event：`workflow_dispatch`
- started：`2026-08-19T10:16:17Z`
- completed：`2026-08-19T10:17:59Z`
- checkout：`1807b9411e398ca3ba2221e4e7a45b03005c0279`
- Maven：72 tests，0 failures，0 errors，0 skipped
- Package：成功
- SSH 配置：成功
- release sync：成功
- systemd restart and verify：成功
- 最终健康结果：`{"status":"UP"}`
- GitHub job 显示耗时：约 1 分 36 秒

这证明了手工选择生产环境的同 SHA 发布路径可以工作。它没有证明真实直播、TOS、MQ 或数据库数据面正常。

## 4. 发布式回滚

现有 workflow 不保存旧 JAR，也没有 rollback input。由于本机没有生产 SSH 私钥，本次采用当前仓库可执行的回滚方式：重新运行发布前最后一次已知成功的生产 Action。

回滚证据：

- 被重新运行的 run ID：`32033664076`
- 新 attempt：`2`
- 原始 event：`pull_request`
- attempt 2 started：`2026-08-19T10:18:37Z`
- attempt 2 completed：`2026-08-19T10:20:14Z`
- 日志确认 checkout：`1807b9411e398ca3ba2221e4e7a45b03005c0279`
- Maven：72 tests，0 failures，0 errors，0 skipped
- Package：成功
- release sync：成功
- systemd restart and verify：成功
- 最终健康结果：`{"status":"UP"}`
- GitHub job 显示耗时：约 1 分 32 秒

该操作验证了“重新构建并部署一个已核验历史 run 所对应的已知良好提交”。它没有恢复发布前 JAR 的原始字节，也没有证明 Maven 构建完全可复现。

## 5. 可进入发布 Skill 的规则

### 发布前

1. 取得明确的生产操作授权和时间窗口。
2. `git fetch origin --prune` 后记录 `origin/prod` 完整 SHA。
3. 确认没有正在运行的同 workflow job。
4. 确认 GitHub 身份具备 Actions 读取和触发权限。
5. 在具备访问能力时检查 `/api/monitoring/status`，避免在活跃直播连接或归档 flush 期间重启。
6. 预先选定一个已知良好的生产 run，并从其日志确认实际 checkout SHA、目标环境和最后健康结果；不能只看 PR head SHA。

### 发布

1. 常规生产发布是将经过批准的 PR 合并到 `prod`，由 `pull_request.closed + merged=true` 自动触发 `deploy.yml`；该路径后续已经由用户人工确认和验证。
2. `workflow_dispatch` 显式选择 `environment=prod` 是本记录已经实证的同 SHA 重部署/特殊操作入口，不取代正常 merge 流程；使用前仍需取得本次生产授权。
3. 无论触发方式，都记录新 run ID、attempt、实际 checkout SHA、开始时间和授权人。
4. 监控 Test、Package、Configure SSH、Sync release、Restart and verify 全部步骤。
5. 任一步失败即停止，不继续声称发布成功。

### 回滚

1. 当前已验证方式是从 GitHub Actions 页面重新运行已核验的历史成功生产 run；后续也可以通过 GitHub API 触发同类操作。
2. 重新运行后必须重新检查日志中的实际 checkout SHA，不能仅依赖页面显示的 PR head branch/head SHA。
3. 同时记录历史 run ID 和新增的 `run_attempt`。
4. 只有重新构建、同步、重启和 `health=UP` 全部成功，才能判断发布式回滚成功。

### 发布后结论分级

1. 构建成功：测试和打包成功。
2. 进程发布成功：制品同步、systemd 重启和 health 成功。
3. 数据面成功：自然直播完成 TOS part/manifest、Legacy MQ、Gateway 和 PostgreSQL 验收。

前两级已在本次实验中验证；第三级尚未验证。

## 6. 尚未验证及后续改进输入

- 发布前活跃连接和进行中归档的机器可判定条件。
- 服务端实际 JAR SHA、PID、启动时间和日志证据。
- 旧 JAR 备份、制品校验和原位恢复。
- readiness 失败后的自动回滚。
- 自然直播事件的端到端数据面验收。
- workflow 中 checkout/setup-java 版本弃用告警的消除。

这些缺口应作为后续发布/恢复方案讨论的输入，不能在当前 Skill 中伪装成已具备能力。

## 7. 2026-08-21 后续确认

- 当前批准的生产日志访问方式是：由人先登录 BytePlus 控制台，再使用获批密钥进入服务器；AI 只提供日志目录、只读命令和结果判读，不索取或保存密钥。
- 该访问规则是后续操作边界，不会补齐本次 2026-08-19 实验当时没有取得的 JAR 校验值、PID、活跃连接和服务器日志证据。
- 生产服务器名、网络地址和当前告警能力统一维护在 [Crawler 接管知识底稿](knowledge-base.md)，避免把后续状态混入本次历史 run 记录。
