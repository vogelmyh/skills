---
name: architecture-boundary-page
description: Analyze one or more code repositories and create a shareable single-page interactive architecture flow with numbered cross-component boundary contracts, then prepare or publish it on GitHub Pages. Use for a repository or one of its business subflows, not for diagrams without code evidence.
---

# 架构流程与边界页面

从当前代码证据生成一张适合跨团队沟通的单页业务图。先遵守各仓库的 `AGENTS.md` 和现有 Pages 约定。

## 输入与证据

开始前明确目标仓库或子流程、上下游仓库、页面输出仓库、标题和 GitHub Pages 目标。

核对每个本地仓库的 `origin`、当前 revision 和工作区状态。以当前实现和类型为准，文档只补充业务语义；不要根据旧文档、示例域名或记忆猜测接口。缺少关键仓库时明确缺口，不要静默替换为同名目录。

沿真实调用链追踪触发入口、协议、存储、异步任务、鉴权、错误与重试边界。区分数据生成、数据读取和用户状态回写，不把同名 Gateway、数据库或消息混为一个组件。

## 页面合同

只生成一个页面。默认使用无框架的自包含 HTML，上方展示流程图，下方展示标点详情：

- 流程图按系统划分泳道，用边界框标出目标仓库内部模块；外部服务放在边界框外。
- 主流程使用醒目实线，补充数据和异步派生使用弱化线或虚线。
- 重要跨组件交互使用 `B1`、`B2` 等稳定编号；优先标记前端入口、鉴权、数据库、消息队列、模型和回写接口。
- 默认选中最关键入口，点击编号后原地更新下方详情，不跳转页面。

每个标点固定说明：

1. 交互方向和组件名称；
2. 接口或协议：HTTP method、完整路径、topic、table、tool 或 RPC；
3. 数据对象和关键字段；
4. 调用方与接收方责任；
5. 鉴权、幂等、事务、重试、失败归属或不触发行为；
6. 已验证的联调示例。环境域名不确定时使用 `{API_ORIGIN}`，不得编造地址。

页面应让读者快速回答“谁调用谁、通过什么接口、传什么、失败由谁处理”。避免大段说明、重复表格和多页导航。

## 交付与 GitHub Pages

- HTML 内嵌样式、脚本和图数据；不得依赖 localhost、本机绝对路径、私有 API、密钥或运行时 `fetch`。
- 桌面端保证流程图可读；窄屏改为纵向摘要和同一套标点详情，不能横向裁切。
- 复用仓库现有 GitHub Pages source、域名和 workflow。若不存在，创建最小静态目录和基于官方 Pages Actions 的部署流程，不引入前端框架。
- 不覆盖已有 Pages 首页或发布流程；发现冲突时先报告并请求选择。
- 远端发布、push、workflow dispatch 和 Pages 设置变更需要当前任务明确授权。未获授权时只交付 Pages-ready 文件和准确发布步骤，不宣称已经上线。

## 验收

- 单文件直接用浏览器打开正常，所有标点可切换；
- 关键接口与当前代码一致，没有秘密、本机路径或失效依赖；
- 检查约 1024px 和 360px 布局；
- Pages 使用仓库子路径打开时资源和交互仍正常；
- 获得发布授权时，以最终 GitHub Pages URL 可访问作为完成条件。

最终交接页面源码路径、Pages URL 或 Pages-ready 状态、核对过的仓库 revision，以及尚未验证的边界。
