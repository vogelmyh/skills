# architecture-boundary-page

从一个或多个代码仓库提取关键业务流程与跨组件边界，生成适合跨团队沟通和 GitHub Pages 发布的单页交互式架构页面。

## When to use

适用于梳理某个仓库或其中一个业务子流程，尤其需要同时说明前端、Gateway、Agent、存储、异步任务或外部服务之间的接口与责任边界时。不适用于缺少代码证据的概念图。

## Invoke

```text
$architecture-boundary-page
```

调用时提供目标仓库、目标子流程、可用的上下游仓库，以及页面标题和 GitHub Pages 目标。具体证据要求、页面合同和发布边界以 [`SKILL.md`](./SKILL.md) 为准。

## Contents

- `SKILL.md`：Codex 指令入口与完整工作流
- `README.md`：面向维护者的概览，不参与运行
