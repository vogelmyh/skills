# LOA Global Crawler 外部交接文档



版本：2026\-08\-19



适用对象：接手 `loa-global-crawler` 开发、运维、数据接入或故障排查的外部同学。



安全说明：本文不包含服务器私钥、数据库密码、Redis/RabbitMQ/TOS 凭据、Euler Key、OAuth Secret、LLM Key、Token 或内网地址。需要凭据时，请通过项目负责人和 GitHub Secrets 的正式流程获取。



## 1\. 交接结论



### 生产代码状态



- **生产代码已全部提交并上线。**

- GitHub 仓库：[`Lighthunter-PTE-ltd/loa-glabal-crawler`](https://github.com/Lighthunter-PTE-ltd/loa-glabal-crawler)。仓库名中的 `glabal` 是现有拼写。

- 生产分支：`prod`。

- 当前远端生产提交：`1807b9411e398ca3ba2221e4e7a45b03005c0279`。

- 最新生产 PR：[\#27 Fix Euler live\-status rate limiting and request amplification](https://github.com/Lighthunter-PTE-ltd/loa-glabal-crawler/pull/27)。

- 最新生产 Action：[32033664076](https://github.com/Lighthunter-PTE-ltd/loa-glabal-crawler/actions/runs/32033664076)，结果 `success`。

- 2026\-08\-19 使用 Java 17 在与 PROD 内容一致的干净工作树上重新执行：72 tests，0 failures，0 errors，`BUILD SUCCESS`。

- 生产健康检查实时返回 `UP`。

- 2026\-08\-19 08:28（Asia/Shanghai）实时快照：188 个主播任务，其中数据库目标 167、公开 API 目标 21；当时有 6 个直播长连接。



### 本地仓库状态



- **当前用户主工作区不是干净状态，不能直接提交或发布。**

- 当前本地分支：`codex/fix-gift-chat-service-wiring`，HEAD `bbfd321`，远端同名分支也是该提交，没有未 push 的 commit。

- 工作区仍有 11 个 tracked modified 文件和 18 个 untracked 文件。

- 其中包括旧实现快照、已经在其他 commit 中提交过的副本、带 ` 2.java` 后缀的重复文件、Playwright 临时产物和本地文档。

- 内容审计显示，直接提交这些文件会删除或倒退 PROD 后续已上线的关键修复，包括 API 身份解析、并发限制、真实 TOS/MQ 路径、归档会话恢复和 Euler 限流。

- 因此结论是：**生产所需代码已提交；本地脏文件不是待发布代码，不能执行全部 add/commit。**

- 未经项目负责人确认，不要 reset、clean、删除或提交该主工作区中的残留文件。



### 环境分支状态



|环境|远端提交|是否包含最新 PROD 修复|
|---|---|---|
|PROD|`1807b94`|是|
|TEST|`0b44233`|否|
|UAT|`ca2ea0c`|否|



- TEST 和 UAT 当前都不包含公开监控 API、归档重启恢复和 PR \#27 Euler 限流等最新 PROD 改动。

- 三个环境不能被视为“代码完全一致、只配置不同”。

- 后续如需对齐，必须从最新 `origin/prod` 建新分支，做环境配置复核后分别通过 PR 合入 TEST/UAT，不能把旧 TEST/UAT 直接 merge 回 PROD。



## 2\. 项目职责



`loa-global-crawler` 是当前线上 TikTok LIVE 爬虫服务，旧附件项目 `loa-crawler` 仅作为早期数据结构和行为参考，不是当前生产进程。



服务负责：



1. 从数据库增量获取需要监控的 LOA 用户。

2. 接受公开 API 添加的非数据库 TikTok 主播。

3. 将目标写入 Redis 共享任务池并在集群节点间分配。

4. 定期检查主播是否开播。

5. 确认开播后建立 TikTok LIVE 长连接。

6. 抓取直播互动事件及参与用户信息。

7. 将直播事件持续归档到 BytePlus TOS。

8. 通过 RabbitMQ 发布实时事件和直播结束通知。

9. 处理 battle/PK 状态消息。

10. 在满足配置条件时，对高价值礼物生成并发送感谢语。



服务不应主动写 MySQL 业务数据。MySQL 用于读取主播目标和身份；Redis、TOS 和 RabbitMQ 是主要写入依赖。



## 3\. 代码入口与分层



项目采用 Spring Boot \+ Java 17，核心分层：



- `gateway`：外部 API、RabbitMQ、TOS 等边界。

- `state`：主播任务、battle window、运行状态和去重状态。

- `harness`：调度、直播检查、连接、事件归档和状态推进。

- `service`：Euler、身份解析、Redis 集群注册、MQ、Gift Chat 等能力。

- `controller`：监控状态、公开主播注册、Euler OAuth 等 HTTP 接口。



推荐阅读顺序：



1. `GlobalCrawlerHarness`

2. `LiveMonitoringHarness`

3. `StreamerWatchStateStore`

4. `ClusterTargetRegistry`

5. `TikTokLiveStatusService`

6. `LiveEventArchiveHarness`

7. `MonitorEventMQService`



权威仓库文档：



- [README\.md](https://github.com/Lighthunter-PTE-ltd/loa-glabal-crawler/blob/prod/README.md)

- [docs/crawler\-data\-contract\.md](https://github.com/Lighthunter-PTE-ltd/loa-glabal-crawler/blob/prod/docs/crawler-data-contract.md)



## 4\. 主播目标获取



### 数据库目标



- 爬虫自身执行数据库增量同步。

- 新用户按递增游标分批读取，避免每次全表扫描。

- 默认增量轮询约 30 秒，单批 500。

- 已有用户通过 refresh cursor 分页复核，默认约 5 分钟一批 500。

- 数据库目标包含真实 LOA GUID、TikTok username/numeric ID、优先级等身份信息。



### 公开 API 目标



公开接口允许外部系统添加一个或多个非数据库主播：



```HTTP
POST https://crawler.loa.services/api/monitoring/public/tasks/start
Content-Type: application/json
```



单个目标：



```JSON
{
  "tiktok_user_id": "example_streamer"
}
```



多个目标：



```JSON
{
  "tiktok_user_ids": ["streamer_a", "@streamer_b"]
}
```



行为：



- 去除 `@`，按规范化 TikTok ID 去重。

- 单次最多接收 100 个目标。

- 请求后立即在当前并发容量内发起首批状态检查，其余由调度器继续处理。

- API 目标进入 Redis 任务池，不是一次性内存任务。

- 公开接口按产品要求无业务鉴权，因此需要监控滥用和任务池增长。



### 身份优先级



- 数据库 LOA 用户：使用真实 `loaUserGuid`，`is_loa_user=true`。

- 纯 API 用户：使用 TikTok ID 作为归档身份，`is_loa_user=false`。

- API 添加的 TikTok ID 如果能匹配数据库真实用户，数据库身份优先。

- 不得因为 API 重复添加同一 TikTok ID，就把真实 LOA GUID 降级成 TikTok ID。



## 5\. Redis 与集群协作



- 所有节点共享 Redis target registry、due queue 和 lease。

- 同一 streamer key 的写入是幂等的，多台爬虫同步同一用户不会生成多个逻辑目标。

- 某一时刻只有持有 Redis lease 的节点负责目标，避免多机重复抓取。

- 节点宕机后 lease 过期，其他节点重新认领。

- 单机环境也会持续分批处理全部目标。

- 服务重启后不需要人工重新导入用户：Redis 目标池仍在，数据库增量/刷新同步也会继续补齐。

- 每 15 秒调度一次；`max-concurrent-status-checks=20` 表示每批最多并发 20 个状态检查，不是服务器只能管理 20 个主播。



## 6\. 直播在线检查



当前模式：`scheduled_live_status_check`，不依赖 Euler Alert 回调。



默认主播检查周期约 5 分钟，并带 jitter。明确离线前还有短间隔确认逻辑。



Euler 主检查：



```Plain Text
Base: https://tiktok.enterprise.eulerstream.com
GET /webcast/anchors/{unique_id}/room_id
```



状态规则：



- 400/404/410：明确离线。

- 429/401/403：返回 UNKNOWN，进入进程级退避；不删除任务，不判定直播结束。

- Euler 5xx/网络异常：执行一次 TikTok 直连状态兜底。

- UNKNOWN：按调度周期重新检查。



限流保护：



- 每个爬虫进程最多 100 个 Euler 状态请求/分钟。

- 429/鉴权拒绝后至少退避 90 秒，并尊重更长的 `Retry-After`。

- 已移除无效 `/webcast/fetch` GET fallback 和重复 SDK fallback，避免一次逻辑检查放大成多次请求。



已知供应商问题：Euler 对部分主播仍可能返回内部 500。当前代码会执行一次直连兜底，但仍需持续监控 Euler 错误率。



## 7\. TikTok LIVE 长连接与事件



- 只有确认 LIVE 后才创建正式长连接。

- 每个主播任务独立，不共享会话数据。

- 长连接保持至明确下播、断连或不可恢复终止。

- 核心归档是直播间用户行为和交互事件。

- 纯系统连接事件，如 `SYSTEM_PRE_CONNECTION`、`WEBSOCKET_RESPONSE`、`WEBSOCKET_MESSAGE`、`WEBSOCKET_UNHANDLED_MESSAGE`、`ROOM_INFO`，不作为核心互动归档。

- 事件应保留 actor/from\_user/to\_user、礼物、评论、点赞、PK/LinkMic 等可用结构。



## 8\. TOS 归档合同



### Bucket



- PROD：`loa-crawler`

- TEST/UAT：`loa-crawler-test`



### Object Key



LOA 用户：



```Plain Text
yyyy-MM-dd/<loaUserGuid>/live-<roomId>-<yyyyMMdd-HHmmss>-<sessionShortId>/
```



非 LOA/API 用户：



```Plain Text
yyyy-MM-dd/<tiktokId>/live-<roomId>-<yyyyMMdd-HHmmss>-<sessionShortId>/
```



目录内容：



```Plain Text
manifest.json
part-00001.json
part-00002.json
...
```



### 上传时序



1. 创建会话后上传初始 `manifest.json`。

2. part 达到大小、事件数或 flush 时间条件后生成。

3. 每生成一个 part 就立即上传，不等待下播。

4. part 上传成功后更新 manifest。

5. 会话终止后写入 `live_ended_at` 并上传最终 manifest。



当前默认滚动条件约为：4\.5 MB、2,000 个事件或 60 秒 flush，检查周期 30 秒。



### 强一致性约束



- MQ 中的 `archiveDirectory` 和 `manifestPath` 必须来自归档服务实际确认的 archive snapshot。

- 禁止在 MQ 层重新拼接 session ID 或猜测路径。

- 如果没有确认成功的 archive path，Legacy `live.ended` 必须跳过发布，不能发送一个不存在的 manifest 地址。

- 爬虫重启时应恢复同一 roomId 已有目录和 part 序号，不能为同一场直播创建第二个目录。

- 如果 TOS 列举/恢复失败，宁可不创建新目录，也不能制造同 roomId 的重复归档。



这些约束由 PR \#23\-\#26 和对应测试覆盖。



### JSON 结构规则



- `raw_event_data` 必须是结构化 JSON，不能出现 Java `ClassName@hash` 字符串。

- 只在 `raw_event_data` 内递归处理大小写不敏感的重复 key，避免 Spark `COLUMN_ALREADY_EXISTS`。

- 顶层字段和其他业务对象不执行该 key 重命名。

- part 和 manifest 包含 `is_loa_user`，不得改变既有核心数据结构。



## 9\. RabbitMQ 合同



主要 Exchange：



```Plain Text
openclaw_skill_topic_exchange
```



实时 monitor routing key：



```Plain Text
crawler.event.monitor.<loaUserGuid>
```



主要 monitor event type：



- `live.started`

- `live.ended`

- `comment.created`

- `like.created`

- 项目已映射的其他互动事件



兼容直播结束 routing key：



```Plain Text
user.pk.invitation.response.<loaUserGuid>
```



需要区分两种 `live.ended`：



1. Monitor `live.ended`：实时事件流的一部分。

2. Legacy/兼容 `live.ended`：给旧接收方，包含实际 TOS `archiveDirectory` 和 `manifestPath`。



Battle/PK 另有 `ONGOING` 和 `DONE` 状态消息，不应与直播结束消息混淆。



## 10\. Gift Chat 与 OAuth



- PR \#16、\#17 已上线高价值礼物自动感谢相关代码和 Spring wiring。

- 目标行为：只对满足价值门槛的礼物生成安全、积极、符合直播间语言的感谢语，再调用 Euler Webcast Chat。

- OAuth 入口：`https://crawler.loa.services/euler/authorize-url`

- OAuth redirect：`https://crawler.loa.services/euler/redirect`

- 是否能实际发送聊天取决于当前有效的 OAuth token；代码部署成功不代表授权永不过期。

- 不要将 Client Secret、OAuth token 或 LLM Key 写进 issue、PR、日志或交接文档。



## 11\. HTTP 诊断接口



健康检查：



```HTTP
GET https://crawler.loa.services/actuator/health
```



监控快照：



```HTTP
GET https://crawler.loa.services/api/monitoring/status
```



重点字段：



- `workers.watchTasks`

- `workers.activeConnectionCount`

- `workers.activeConnections`

- `workers.monitoringMode`

- `workers.clusterTargetRegistryEnabled`

- 单任务的 `sources`、`databaseTarget`、`apiTarget`、`lastAttemptAt`、`nextProbeAt`、`lastConnectedAt` 和 `status`



## 12\. 环境配置



配置文件：



- `src/main/resources/application.properties`

- `src/main/resources/application-test.properties`

- `src/main/resources/application-uat.properties`

- `src/main/resources/application-prod.properties`



每套环境必须核对：



- Spring profile

- MySQL 数据库/schema 和只读账号

- Redis namespace/host

- RabbitMQ vhost、账号、exchange 和 routing key

- TOS Bucket、region、node\-id

- Euler Base URL、API Key、限流参数

- OAuth 与 BytePlus LLM 配置



不能把 TEST、UAT、PROD 的数据库、Redis、RabbitMQ 或 TOS 配置混用。



当前发布配置风险：GitHub workflow 中 TEST 默认 host 仍是历史地址，且仓库没有设置 `TEST_DEPLOY_HOST` Repository Variable。下一次 TEST 发布前必须由项目负责人确认真实服务器并修正变量或 workflow。



## 13\. 正常发布流程



1. `git fetch origin`。

2. 从目标环境最新分支或 `origin/prod` 创建全新干净 worktree。

3. 创建 `codex/...` 功能分支。

4. 只提交目标变更，不带本地主工作区残留。

5. 使用 Java 17 执行 `mvn -B test`。

6. 执行 `mvn -B -DskipTests package`。

7. Push 功能分支并创建 PR 到 `test`、`uat` 或 `prod`。

8. PR 合并后由 GitHub Actions 打包、SSH 同步、重启 systemd 并检查 health。

9. 发布后必须验证任务池、直播连接、TOS part、manifest 和 MQ，而不能只看 Action 绿色。



禁止：



- 从当前脏主工作区直接 `git add -A`。

- 直接将旧 TEST/UAT 合并回 PROD。

- 手动修改生产文件后不回写 Git。

- 只重启服务、不确认 Spring profile。

- 在 PR 中打印配置文件里的明文凭据。



## 14\. 发布后验收清单



1. `/actuator/health` 为 `UP`。

2. `/api/monitoring/status` 中数据库目标和 API 目标都存在。

3. 调度时间持续推进，没有大批任务永久停留在 `PROBING`。

4. Euler 没有持续 429；5xx 不形成请求放大。

5. 找一场真实直播确认长连接成功。

6. TOS 持续生成 part，而不是只在下播时上传。

7. 初始、增量和最终 manifest 都存在。

8. `live_ended_at` 正确。

9. Legacy MQ `manifestPath` 与 TOS 实际 key 字符级一致。

10. 同一 roomId 没有因重启或短暂断线产生第二个目录。

11. 数据库用户使用真实 GUID 和 `is_loa_user=true`。

12. API 非 LOA 用户使用 TikTok ID 和 `is_loa_user=false`。



## 15\. 最近关键生产 PR



- [\#18 Public TikTok monitoring API](https://github.com/Lighthunter-PTE-ltd/loa-glabal-crawler/pull/18)

- [\#19 API archive identity resolution](https://github.com/Lighthunter-PTE-ltd/loa-glabal-crawler/pull/19)

- [\#20 API identity lookup hardening](https://github.com/Lighthunter-PTE-ltd/loa-glabal-crawler/pull/20)

- [\#21 Textual TikTok identity](https://github.com/Lighthunter-PTE-ltd/loa-glabal-crawler/pull/21)

- [\#22 Production TikTok account schema](https://github.com/Lighthunter-PTE-ltd/loa-glabal-crawler/pull/22)

- [\#23 Live\-ended archive paths](https://github.com/Lighthunter-PTE-ltd/loa-glabal-crawler/pull/23)

- [\#24 Ended session reuse](https://github.com/Lighthunter-PTE-ltd/loa-glabal-crawler/pull/24)

- [\#25 Authoritative MQ archive paths](https://github.com/Lighthunter-PTE-ltd/loa-glabal-crawler/pull/25)

- [\#26 Archive session resume across restarts](https://github.com/Lighthunter-PTE-ltd/loa-glabal-crawler/pull/26)

- [\#27 Euler rate\-limit and request amplification](https://github.com/Lighthunter-PTE-ltd/loa-glabal-crawler/pull/27)



## 16\. 已知风险



1. TEST/UAT 分支落后 PROD，代码并不一致。

2. TEST GitHub Action 默认服务器配置存在历史地址风险。

3. TEST 和 PROD 可能共享 Euler 账户额度，跨环境请求会共同消耗 quota。

4. Euler 仍可能返回供应商内部 500。

5. 公开监控 API 无鉴权，存在滥用和配额膨胀风险。

6. 历史 TOS 错误目录或已发送错误 MQ 不会被新代码自动迁移。

7. 当前本地主工作区有残留文件，任何发布都必须从干净 worktree 开始。



## 17\. 故障排查顺序



### 主播没有被监控



1. 查 `workers.watchTasks` 是否存在主播。

2. 确认 `databaseTarget` 或 `apiTarget`。

3. 查 `lastAttemptAt`、`nextProbeAt`、`probing`。

4. 查 Euler 429/5xx/UNKNOWN 日志。

5. 查 Redis lease 是否由其他节点持有。

6. 确认 LIVE 后再查长连接异常。



### 有直播但没有 TOS



1. 确认 active connection。

2. 查 `Archive session prepared`。

3. 查 `Uploaded live archive part`。

4. 查 Bucket/profile 是否正确。

5. 查 TOS PUT/list 错误。

6. 不要仅依赖 `live.ended` 判断是否应该有 part。



### MQ 路径不存在



1. 用 MQ 的 `manifestPath` 直接查 TOS。

2. 查归档 harness confirmed snapshot。

3. 确认没有由 MQ 层重新拼路径。

4. 同 roomId 搜索是否存在多个目录。

5. 检查是否为历史旧消息，而不是当前版本新消息。



### 同 roomId 两个目录



1. 查服务是否在直播期间重启。

2. 查 TOS list/recovery 是否失败。

3. 查 manifest 的 roomId、start time、completed、updated\_at。

4. 新版本应恢复最近正确目录并延续 part 序号。



## 18\. Suggested Skills



- `diagnosing-bugs`：直播漏检、Euler 异常、归档和 MQ 路径问题。

- `code-review`：生产发布前检查规格、变更范围和回归风险。

- `github:gh-fix-ci`：GitHub Actions 失败排查。

- `github:yeet`：用户明确要求发布时，规范完成提交、push 和 PR。



## 19\. 外部同学接手原则



- 任何“已上线”结论都必须同时给出 commit、PR、Action、health 和业务证据。

- 任何路径问题都以 TOS 实际 object key 为准，不能推导。

- 任何主播身份问题都要区分 TikTok username、numeric ID、LOA GUID 和目标来源。

- 任何当前数量、直播状态或配额都要实时查询，不能复用旧截图。

- 不输出凭据，不将本地临时文件或历史对话中的 Key 带入 Git。

- 对当前本地主工作区只读审计，除非项目负责人明确授权清理。
