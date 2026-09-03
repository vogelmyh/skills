# greenfield-requirement-design

为尚无既有产品行为或源码实现需要保留的非平凡全新需求完成需求侦察、关键决策和最小充分设计，产出可供后续实现与审查独立使用的冻结规格。

## When to use

仅在用户显式调用 `$greenfield-requirement-design` 时使用。适合在全新产品、服务、组件或独立能力开始实现之前，明确用户场景、系统边界、约束、架构责任和验收方式。不适用于依赖既有实现现状的增量变更、简单任务或已冻结规格的实现。

## Invoke

```text
$greenfield-requirement-design
```

调用时提供需求、用户或问题背景、目标平台、相关约束和已有文档。具体设计边界、决策流程、规格格式与停止条件以 [`SKILL.md`](./SKILL.md) 为准。

冻结后的 `SPEC.md` 可在独立上下文中交给 `implement-frozen-spec` 实施，再由 `review-spec-implementation` 独立审查。

## Contents

- `SKILL.md`：Codex 指令入口与完整工作流
- `agents/openai.yaml`：关闭隐式调用的调用策略
- `README.md`：面向维护者的概览，不参与运行

该 skill 是独立单元，不读取既有产品源码来推导设计，也不要求仓库级 `AGENTS.md` 或其他同组 skill 才能执行。
