# 直播结束 MQ 对接说明



## 1\. 结论



爬虫明确收到 TikTok SDK 的 `onLiveEnded` 事件后，会按顺序向 RabbitMQ 发送两条 `eventType=live.ended` 消息：



1. Legacy 直播结束消息：包含 TOS 归档目录及 `manifest.json` 路径。

2. Monitor 直播结束消息：统一的直播监控事件格式。



普通 WebSocket 断开 `onDisconnected` 不等同于明确下播，当前不会发送这两条 MQ。



消息体是 UTF\-8 JSON。两条消息都发送到 topic exchange：



```Plain Text
openclaw_skill_topic_exchange
```



## 2\. Legacy 直播结束消息



Routing key：



```Plain Text
user.pk.invitation.response.<loaUserGuid>
```



示例：



```JSON
{
  "eventId": "f175c177-6a9d-4dcc-b5a7-bd97cbd1167a",
  "eventType": "live.ended",
  "message": "Live ended for example_host in room 7646197574328306446 at 2026-08-06T18:30:00.",
  "data": {
    "guid": "loa-user-guid",
    "roomId": "7646197574328306446",
    "sessionId": "e2ef6318-50b7-45fc-b615-342158deee13",
    "liveStartedAt": 1786008600000,
    "liveEndedAt": 1786012200000,
    "archiveDirectory": "2026-08-06/loa-user-guid/live-7646197574328306446-20260806-173000-e2ef6318",
    "manifestPath": "2026-08-06/loa-user-guid/live-7646197574328306446-20260806-173000-e2ef6318/manifest.json",
    "streamer": {
      "guid": "loa-user-guid",
      "usernameTK": "example_host",
      "userIdTk": "1234567890",
      "nickname": "Example Host",
      "avatarUrl": ""
    }
  }
}
```



PROD bucket 是 `loa-crawler`，因此完整 manifest 位置为：



```Plain Text
tos://loa-crawler/<manifestPath>
```



`manifestPath` 本身只包含 object key，不包含 bucket 名和 `tos://` 前缀。



## 3\. Monitor 直播结束消息



Routing key：



```Plain Text
crawler.event.monitor.<loaUserGuid>
```



示例：



```JSON
{
  "eventId": "287e39cf-75ec-423a-80c8-60c6e5c97746",
  "eventType": "live.ended",
  "message": "Live ended for example_host in room 7646197574328306446 at 2026-08-06T18:30:00.",
  "data": {
    "roomId": "7646197574328306446",
    "sessionId": "e2ef6318-50b7-45fc-b615-342158deee13",
    "liveStartedAt": 1786008600000,
    "streamer": {
      "guid": "loa-user-guid",
      "usernameTK": "example_host",
      "userIdTk": "1234567890",
      "nickname": "Example Host"
    },
    "liveEndedAt": 1786012200000
  }
}
```



## 4\. 字段说明



|字段|说明|
|---|---|
|`eventId`|每条 MQ 独立生成的 UUID；两条结束消息的值不同|
|`eventType`|固定为 `live.ended`|
|`guid` / `streamer.guid`|LOA 用户 GUID；公开 API 的非 LOA 主播使用 TikTok ID|
|`roomId`|TikTok 直播间 room ID|
|`sessionId`|本场直播归档 session UUID|
|`liveStartedAt`|直播开始时间，epoch milliseconds|
|`liveEndedAt`|爬虫确认直播结束的时间，epoch milliseconds|
|`archiveDirectory`|本场直播在 TOS 内的相对目录|
|`manifestPath`|本场直播 `manifest.json` 的 TOS object key|



Routing key 中的 GUID 仅保留字母、数字、`.`、`_`、`-`；其他字符会替换成 `_`。



## 5\. 接收方建议



- 需要归档地址时，绑定 `user.pk.invitation.response.*`。

- 需要统一监控事件时，绑定 `crawler.event.monitor.*`。

- 建议以 `eventId` 做消息幂等；同一场直播的两类消息不能用 `eventId` 互相去重。

- 如需关联两条结束消息，可使用 `data.sessionId`，并辅助校验 `roomId`。

- Producer 当前发布时没有设置自定义 AMQP properties，接收方直接把 body 按 UTF\-8 JSON 解析。
